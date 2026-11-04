// Agilex 7 AGM039 soft datapath for an 8-port 128G Fibre Channel bridge.
//
// Hardened F-Tile PMA sits outside this module:
//   * client_*  is one FHT lane per 112.2G PAM4 128GFC port
//   * sys_*     is the FGT pair (2 x 58G) bonded to that port
//   * sec_*     is the extra 8 x 58G bank (protect copy or squelch)
//
// The block coding, ordered sets, and frame-pipe RS(255,239) FEC are the PoC
// mapping of the proposal's soft pipeline (PCS, FEC, framing, credit, gearbox,
// link init). Control blocks carry the FC-FS ordered set in [31:0]. CSR bit 5
// packs each system direction into Clause 119 256b/257b words. FC-PI-8
// RS(544,514) over GF(2^10) is fc_rs544. A codeword is 544 ten-bit symbols,
// so that engine stays off the 256-byte frame RAM. Ordered sets are in
// fc128_defs.vh.
module fc128_bridge_top #(
  parameter int N_CLIENT       = 8,
  parameter int MAX_PAY        = 128,
  parameter int DEFAULT_CREDIT = 8
) (
  input  logic clk_client,
  input  logic clk_system,
  input  logic rst_client_n,
  input  logic rst_system_n,

  input  logic [11:0] csr_addr,
  input  logic        csr_write,
  input  logic        csr_read,
  input  logic [31:0] csr_wdata,
  output logic [31:0] csr_rdata,

  input  logic [N_CLIENT-1:0]       client_rx_valid,
  output logic [N_CLIENT-1:0]       client_rx_ready,
  input  logic [N_CLIENT-1:0][1:0]  client_rx_sync,
  input  logic [N_CLIENT-1:0][63:0] client_rx_data,
  output logic [N_CLIENT-1:0]       client_tx_valid,
  input  logic [N_CLIENT-1:0]       client_tx_ready,
  output logic [N_CLIENT-1:0][1:0]  client_tx_sync,
  output logic [N_CLIENT-1:0][63:0] client_tx_data,

  output logic [2*N_CLIENT-1:0]       sys_tx_valid,
  input  logic [2*N_CLIENT-1:0]       sys_tx_ready,
  output logic [2*N_CLIENT-1:0][1:0]  sys_tx_sync,
  output logic [2*N_CLIENT-1:0][63:0] sys_tx_data,
  input  logic [2*N_CLIENT-1:0]       sys_rx_valid,
  output logic [2*N_CLIENT-1:0]       sys_rx_ready,
  input  logic [2*N_CLIENT-1:0][1:0]  sys_rx_sync,
  input  logic [2*N_CLIENT-1:0][63:0] sys_rx_data,

  output logic [N_CLIENT-1:0]       sec_tx_valid,
  output logic [N_CLIENT-1:0][1:0]  sec_tx_sync,
  output logic [N_CLIENT-1:0][63:0] sec_tx_data
);
  localparam [31:0] ID_WORD  = 32'hFC12_8039;
  localparam [31:0] VER_WORD = 32'h0001_0001;

  logic        sw_reset;
  logic        sys_loopback;
  logic        fec_en;
  logic        scrambler_en;
  logic        sec_protect;
  logic        xcode_en;
  logic [31:0] scratch;
  logic [N_CLIENT-1:0] port_en;
  logic        credit_load;
  logic [7:0]  credit_cli_i;
  logic [7:0]  credit_sys_i;

  logic [1:0] rst_c_ff;
  logic [1:0] rst_csr_ff;
  logic [1:0] rst_s_ff;
  wire        rst_c_async_n = rst_client_n & ~sw_reset;
  wire        rst_s_async_n = rst_system_n & ~sw_reset;

  always_ff @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n)
      rst_csr_ff <= 2'b00;
    else
      rst_csr_ff <= {rst_csr_ff[0], 1'b1};
  end

  always_ff @(posedge clk_client or negedge rst_c_async_n) begin
    if (!rst_c_async_n)
      rst_c_ff <= 2'b00;
    else
      rst_c_ff <= {rst_c_ff[0], 1'b1};
  end

  always_ff @(posedge clk_system or negedge rst_s_async_n) begin
    if (!rst_s_async_n)
      rst_s_ff <= 2'b00;
    else
      rst_s_ff <= {rst_s_ff[0], 1'b1};
  end

  wire rst_csr_n = rst_csr_ff[1];
  wire rst_c_n   = rst_c_ff[1];
  wire rst_s_n   = rst_s_ff[1];

  logic [1:0] scr_s_ff;
  logic [1:0] lb_s_ff;
  logic [1:0] sec_s_ff;
  always_ff @(posedge clk_system or negedge rst_s_n) begin
    if (!rst_s_n) begin
      scr_s_ff <= 2'b00;
      lb_s_ff  <= 2'b00;
      sec_s_ff <= 2'b00;
    end else begin
      scr_s_ff <= {scr_s_ff[0], scrambler_en};
      lb_s_ff  <= {lb_s_ff[0], sys_loopback};
      sec_s_ff <= {sec_s_ff[0], sec_protect};
    end
  end
  wire scrambler_en_s = scr_s_ff[1];
  wire loopback_s     = lb_s_ff[1];
  wire sec_protect_s  = sec_s_ff[1];

  logic [N_CLIENT-1:0]       p_lock;
  logic [N_CLIENT-1:0][7:0]  p_cli;
  logic [N_CLIENT-1:0][7:0]  p_sys;
  logic [N_CLIENT-1:0][31:0] p_rx;
  logic [N_CLIENT-1:0][31:0] p_tx;
  logic [N_CLIENT-1:0][31:0] p_crc;
  logic [N_CLIENT-1:0][31:0] p_corr;
  logic [N_CLIENT-1:0][31:0] p_fail;
  logic [N_CLIENT-1:0]       p_client_up;
  logic [N_CLIENT-1:0]       p_system_up;
  logic [N_CLIENT-1:0]       p_sys_lock;
  logic [N_CLIENT-1:0][2:0]  p_client_ls;
  logic [N_CLIENT-1:0][2:0]  p_system_ls;

  logic [2*N_CLIENT-1:0]       port_sys_rx_valid;
  logic [2*N_CLIENT-1:0]       port_sys_rx_ready;
  logic [2*N_CLIENT-1:0][1:0]  port_sys_rx_sync;
  logic [2*N_CLIENT-1:0][63:0] port_sys_rx_data;
  logic [2*N_CLIENT-1:0]       port_sys_tx_valid;
  logic [2*N_CLIENT-1:0]       port_sys_tx_ready;
  logic [2*N_CLIENT-1:0][1:0]  port_sys_tx_sync;
  logic [2*N_CLIENT-1:0][63:0] port_sys_tx_data;

  genvar gi;
  generate
    for (gi = 0; gi < 2*N_CLIENT; gi = gi + 1) begin : g_lb
      assign port_sys_rx_valid[gi] = loopback_s ? port_sys_tx_valid[gi] : sys_rx_valid[gi];
      assign port_sys_rx_sync[gi]  = loopback_s ? port_sys_tx_sync[gi]  : sys_rx_sync[gi];
      assign port_sys_rx_data[gi]  = loopback_s ? port_sys_tx_data[gi]  : sys_rx_data[gi];
      assign port_sys_tx_ready[gi] = loopback_s ? port_sys_rx_ready[gi] : sys_tx_ready[gi];
      assign sys_tx_valid[gi]      = port_sys_tx_valid[gi];
      assign sys_tx_sync[gi]       = port_sys_tx_sync[gi];
      assign sys_tx_data[gi]       = port_sys_tx_data[gi];
      assign sys_rx_ready[gi]      = loopback_s ? 1'b0 : port_sys_rx_ready[gi];
    end
  endgenerate

  generate
    for (gi = 0; gi < N_CLIENT; gi = gi + 1) begin : g_port
      fc_port #(
        .MAX_PAY        (MAX_PAY),
        .DEFAULT_CREDIT (DEFAULT_CREDIT)
      ) u_port (
        .clk_client      (clk_client),
        .rst_client_n    (rst_c_n),
        .clk_system      (clk_system),
        .rst_system_n    (rst_s_n),
        .port_en         (port_en[gi]),
        .fec_en          (fec_en),
        .scrambler_en    (scrambler_en),
        .scrambler_en_s  (scrambler_en_s),
        .xcode_en        (xcode_en),
        .credit_load     (credit_load),
        .credit_cli_i    (credit_cli_i),
        .credit_sys_i    (credit_sys_i),
        .client_rx_valid (client_rx_valid[gi]),
        .client_rx_ready (client_rx_ready[gi]),
        .client_rx_sync  (client_rx_sync[gi]),
        .client_rx_data  (client_rx_data[gi]),
        .client_tx_valid (client_tx_valid[gi]),
        .client_tx_ready (client_tx_ready[gi]),
        .client_tx_sync  (client_tx_sync[gi]),
        .client_tx_data  (client_tx_data[gi]),
        .sys_tx_valid    (port_sys_tx_valid[2*gi +: 2]),
        .sys_tx_ready    (port_sys_tx_ready[2*gi +: 2]),
        .sys_tx_sync     (port_sys_tx_sync[2*gi +: 2]),
        .sys_tx_data     (port_sys_tx_data[2*gi +: 2]),
        .sys_rx_valid    (port_sys_rx_valid[2*gi +: 2]),
        .sys_rx_ready    (port_sys_rx_ready[2*gi +: 2]),
        .sys_rx_sync     (port_sys_rx_sync[2*gi +: 2]),
        .sys_rx_data     (port_sys_rx_data[2*gi +: 2]),
        .client_lock     (p_lock[gi]),
        .credit_cli      (p_cli[gi]),
        .credit_sys      (p_sys[gi]),
        .stat_rx_frames  (p_rx[gi]),
        .stat_tx_frames  (p_tx[gi]),
        .stat_crc_err    (p_crc[gi]),
        .stat_fec_corr   (p_corr[gi]),
        .stat_fec_fail   (p_fail[gi]),
        .client_link_up  (p_client_up[gi]),
        .system_link_up  (p_system_up[gi]),
        .client_ls       (p_client_ls[gi]),
        .system_ls       (p_system_ls[gi]),
        .sys_locked      (p_sys_lock[gi])
      );

      // Secondary 58G bank. Protect mode mirrors the even lane of the pair
      // (the first block of every stripe). Squelch drops the lane.
      assign sec_tx_valid[gi] = sec_protect_s ? port_sys_tx_valid[2*gi] : 1'b0;
      assign sec_tx_sync[gi]  = sec_protect_s ? port_sys_tx_sync[2*gi]  : 2'b00;
      assign sec_tx_data[gi]  = sec_protect_s ? port_sys_tx_data[2*gi]  : 64'h0;
    end
  endgenerate

  always_ff @(posedge clk_client or negedge rst_csr_n) begin
    if (!rst_csr_n) begin
      sw_reset      <= 1'b0;
      sys_loopback  <= 1'b0;
      fec_en        <= 1'b0;
      scrambler_en  <= 1'b0;
      sec_protect   <= 1'b0;
      xcode_en      <= 1'b0;
      scratch       <= 32'h0;
      port_en       <= '0;
      credit_load   <= 1'b0;
      credit_cli_i  <= 8'(DEFAULT_CREDIT);
      credit_sys_i  <= 8'(DEFAULT_CREDIT);
    end else begin
      credit_load <= 1'b0;
      if (csr_write) begin
        case (csr_addr)
          12'h008: begin
            sw_reset     <= csr_wdata[0];
            sys_loopback <= csr_wdata[1];
            fec_en       <= csr_wdata[2];
            scrambler_en <= csr_wdata[3];
            sec_protect  <= csr_wdata[4];
            xcode_en     <= csr_wdata[5];
          end
          12'h010: port_en <= csr_wdata[N_CLIENT-1:0];
          12'h014: scratch <= csr_wdata;
          12'h018: begin
            credit_sys_i <= csr_wdata[7:0];
            credit_cli_i <= csr_wdata[15:8];
            credit_load  <= 1'b1;
          end
          default: ;
        endcase
      end
    end
  end

  logic [31:0] rdata_mux;
  logic [2:0]  port_idx;
  always_comb begin
    rdata_mux = 32'h0;
    port_idx  = csr_addr[7:5];
    case (csr_addr)
      12'h000: rdata_mux = ID_WORD;
      12'h004: rdata_mux = VER_WORD;
      12'h008: rdata_mux = {26'h0, xcode_en, sec_protect, scrambler_en, fec_en,
                             sys_loopback, sw_reset};
      12'h00C: rdata_mux = {{(32-N_CLIENT){1'b0}}, p_lock};
      12'h010: rdata_mux = {{(32-N_CLIENT){1'b0}}, port_en};
      12'h014: rdata_mux = scratch;
      12'h018: rdata_mux = {16'h0, p_cli[0], p_sys[0]};
      12'h01C: rdata_mux = {{(32-N_CLIENT){1'b0}}, p_client_up};
      12'h020: rdata_mux = {{(32-N_CLIENT){1'b0}}, p_system_up};
      12'h028: rdata_mux = {{(32-N_CLIENT){1'b0}}, p_sys_lock};
      default: begin
        if (csr_addr[11:8] == 4'h1 && csr_addr[7:5] < N_CLIENT) begin
          case (csr_addr[4:2])
            3'd0: rdata_mux = p_rx[port_idx];
            3'd1: rdata_mux = p_tx[port_idx];
            3'd2: rdata_mux = p_crc[port_idx];
            3'd3: rdata_mux = p_corr[port_idx];
            3'd4: rdata_mux = p_fail[port_idx];
            3'd5: rdata_mux = {15'h0, p_lock[port_idx], p_cli[port_idx], p_sys[port_idx]};
            3'd6: rdata_mux = {16'h0, 2'b00, p_system_ls[port_idx], p_client_ls[port_idx],
                               6'h0, p_system_up[port_idx], p_client_up[port_idx]};
            default: rdata_mux = 32'h0;
          endcase
        end
      end
    endcase
  end

  assign csr_rdata = csr_read ? rdata_mux : 32'h0;
endmodule
