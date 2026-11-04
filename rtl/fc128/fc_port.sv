// One FC128 client port.
// Client PMA is one lane. The system side is a bonded pair (the 1:2 gearbox).
// Frame payload crosses client -> system and system -> client. R_RDY and
// buffer-to-buffer credit stay on the link that owns them.
//
// Each physical link has its own fc_link_sm. The client machine watches the
// client ingress and chooses the primitive the system-to-client pipe sends.
// The system machine watches the merged system ingress and chooses the
// primitive the client-to-system pipe sends. Frames stay off a link until
// that machine reaches Active.
//
// rate is the per-port line rate (fc128_defs.vh). 128GFC stripes both system
// lanes. 64GFC and 32GFC use lane 0, and block lock follows that lane.
// 32GFC inserts one IDLE per block in front of the transcode and deletes it
// on the merged stream, before this port's link machine and frame pipe.
// A new rate while the port is out of reset holds both link machines down,
// waits until both pipes are between frames, then clears the shaper, the
// transcode, the RS(544,514) stream, and the lane FIFOs onto the new map.
// Block lock and the scramblers keep running. rate_busy stays set until
// that apply finishes.
module fc_port #(
  parameter int MAX_PAY        = 128,
  parameter int FIFO_DEPTH     = 32,
  parameter int DEFAULT_CREDIT = 8
) (
  input  logic        clk_client,
  input  logic        rst_client_n,
  input  logic        clk_system,
  input  logic        rst_system_n,

  input  logic        port_en,
  input  logic        fec_en,
  input  logic        scrambler_en,
  input  logic        scrambler_en_s,
  input  logic        xcode_en,
  input  logic        rs544_en,
  input  logic [1:0]  rate,
  input  logic        credit_load,
  input  logic [7:0]  credit_cli_i,
  input  logic [7:0]  credit_sys_i,

  input  logic        client_rx_valid,
  output logic        client_rx_ready,
  input  logic [1:0]  client_rx_sync,
  input  logic [63:0] client_rx_data,
  output logic        client_tx_valid,
  input  logic        client_tx_ready,
  output logic [1:0]  client_tx_sync,
  output logic [63:0] client_tx_data,

  output logic [1:0]       sys_tx_valid,
  input  logic [1:0]       sys_tx_ready,
  output logic [1:0][1:0]  sys_tx_sync,
  output logic [1:0][63:0] sys_tx_data,
  input  logic [1:0]       sys_rx_valid,
  output logic [1:0]       sys_rx_ready,
  input  logic [1:0][1:0]  sys_rx_sync,
  input  logic [1:0][63:0] sys_rx_data,

  output logic        client_lock,
  output logic [7:0]  credit_cli,
  output logic [7:0]  credit_sys,
  output logic [31:0] stat_rx_frames,
  output logic [31:0] stat_tx_frames,
  output logic [31:0] stat_crc_err,
  output logic [31:0] stat_fec_corr,
  output logic [31:0] stat_fec_fail,
  output logic [15:0] stat_rs544_corr,
  output logic [15:0] stat_rs544_fail,
  output logic        client_link_up,
  output logic        system_link_up,
  output logic [2:0]  client_ls,
  output logic [2:0]  system_ls,
  output logic        sys_locked,
  output logic        rate_busy
);
  logic        c_rx_ready, c_tx_valid, c_tx_ready;
  logic [1:0]  c_rx_sync, c_tx_sync;
  logic [63:0] c_rx_data, c_tx_data;
  logic        c_tx_to_split_valid;
  logic        s_pipe_tx_valid;
  logic [1:0]  c_tx_to_split_sync;
  logic [1:0]  s_pipe_tx_sync;
  logic [63:0] c_tx_to_split_data;
  logic [63:0] s_pipe_tx_data;
  logic        rate_tx_valid;
  logic        rate_tx_ready;
  logic [1:0]  rate_tx_sync;
  logic [63:0] rate_tx_data;
  logic        rate_rx_valid;
  logic        rate_rx_in_ready;
  logic        rate_pipe_ready;
  logic [1:0]  rate_rx_sync;
  logic [63:0] rate_rx_data;
  logic        c2s_take, s2c_take, c2s_rrdy, s2c_rrdy;
  logic        c2s_idle, s2c_idle;
  logic        c2s_acc, s2c_acc;
  logic [31:0] c2s_rx, c2s_tx, c2s_crc, c2s_corr, c2s_fail;
  logic [31:0] s2c_rx, s2c_tx, s2c_crc, s2c_corr, s2c_fail;
  logic [7:0]  cli_cr, sys_cr;
  logic [8:0]  cli_next, sys_next;

  logic        split_ready;
  logic        x_in_ready;
  logic        x_to_split_valid;
  logic [1:0]  x_to_split_sync;
  logic [63:0] x_to_split_data;
  logic        rs_tx_ready;
  logic        rs_to_split_valid;
  logic [1:0]  rs_to_split_sync;
  logic [63:0] rs_to_split_data;
  logic        rs_rx_valid;
  logic        rs_rx_ready;
  logic [1:0]  rs_rx_sync;
  logic [63:0] rs_rx_data;
  logic        rs_corr_pulse;
  logic        rs_fail_pulse;
  logic [4:0]  rs_corr_nerr;
  logic [15:0] rs544_corr;
  logic [15:0] rs544_fail;
  logic        dec_valid;
  logic        dec_ready;
  logic [1:0]  dec_sync;
  logic [63:0] dec_data;
  logic [1:0]  xcode_meta;
  logic [1:0]  split_valid;
  logic [1:0][1:0] split_sync;
  logic [1:0][63:0] split_data;
  logic [1:0][63:0] sys_tx_scr;
  logic        merge_valid, merge_ready;
  logic [1:0]  merge_sync;
  logic [63:0] merge_data;
  logic [1:0]  sys_lock;
  logic [1:0]  sys_lock_meta;
  logic [1:0]  sys_lock_sync;
  logic [1:0][1:0]  sys_front_sync;
  logic [1:0][63:0] sys_front_data;
  logic [31:0] client_tx_os;
  logic [31:0] system_tx_os;

  // Rate apply. stripe and half change only after the system gearbox has
  // been reset on both clocks, so a live write cannot splice two lane maps.
  localparam [2:0] RH_IDLE  = 3'd0;
  localparam [2:0] RH_DRAIN = 3'd1;
  localparam [2:0] RH_ARM   = 3'd2;
  localparam [2:0] RH_ACK   = 3'd3;
  localparam [2:0] RH_HOLD  = 3'd4;
  localparam [2:0] RH_REL   = 3'd5;

  logic [1:0]  rate_use;
  logic [2:0]  rh;
  logic [3:0]  clr_cnt;
  logic [11:0] drain_cnt;
  logic        stall;
  logic        stall_d;
  logic        link_hold;
  logic        clr_req;
  logic       clr_s1, clr_s2;
  logic       ack1, ack2;
  // 2'b01 is 64GFC and 2'b10 is 32GFC. Anything else, including the reserved
  // encoding, keeps the 128GFC stripe. half is the 32GFC IDLE insert.
  wire [1:0] rate_norm = (rate == 2'b01 || rate == 2'b10) ? rate : 2'b00;
  wire       stripe = (rate_use != 2'b01) && (rate_use != 2'b10);
  wire       half   = (rate_use == 2'b10);
  wire       rst_stream_n = rst_client_n & ~stall;
  wire       rst_fifo_c_n = rst_client_n & ~(clr_req & ack2);
  wire       rst_fifo_s_n = rst_system_n & ~clr_s2;
  wire       credit_reload = stall_d & ~stall;
  wire       pipes_idle = c2s_idle && s2c_idle && !client_link_up && !system_link_up;
  assign     rate_busy = link_hold || (rate_norm != rate_use);

  // System block lock is produced on clk_system. The return pipe and the
  // system link machine both sit on clk_client. stall masks it as soon as
  // the rate write is seen, before the system reset has crossed.
  always_ff @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n) begin
      sys_lock_meta <= 2'b00;
      sys_lock_sync <= 2'b00;
    end else begin
      sys_lock_meta <= sys_lock;
      sys_lock_sync <= sys_lock_meta;
    end
  end
  assign sys_locked = stripe ? (sys_lock_sync[0] & sys_lock_sync[1])
                             : sys_lock_sync[0];
  wire link_ok_c = client_lock & ~link_hold;
  wire link_ok_s = sys_locked & ~link_hold;

  always_ff @(posedge clk_system or negedge rst_system_n) begin
    if (!rst_system_n) begin
      clr_s1 <= 1'b0;
      clr_s2 <= 1'b0;
    end else begin
      clr_s1 <= clr_req;
      clr_s2 <= clr_s1;
    end
  end

  always_ff @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n) begin
      ack1      <= 1'b0;
      ack2      <= 1'b0;
      rate_use  <= rate_norm;
      rh        <= RH_IDLE;
      clr_cnt   <= 4'h0;
      drain_cnt <= 12'h0;
      stall     <= 1'b0;
      stall_d   <= 1'b0;
      link_hold <= 1'b0;
      clr_req   <= 1'b0;
    end else begin
      ack1    <= clr_s2;
      ack2    <= ack1;
      stall_d <= stall;
      case (rh)
        RH_IDLE: begin
          stall     <= 1'b0;
          link_hold <= 1'b0;
          clr_req   <= 1'b0;
          drain_cnt <= 12'h0;
          if (rate_norm != rate_use) begin
            link_hold <= 1'b1;
            rh        <= RH_DRAIN;
          end
        end
        // Links are down. Let a frame already in either pipe finish on the
        // old lane map, then clear the system path. The drain cap stops a
        // wedged frame from holding the old rate forever.
        RH_DRAIN: begin
          stall     <= 1'b0;
          link_hold <= 1'b1;
          clr_req   <= 1'b0;
          if (pipes_idle || drain_cnt == 12'hFFF) begin
            rh <= RH_ARM;
          end else begin
            drain_cnt <= drain_cnt + 12'd1;
          end
        end
        RH_ARM: begin
          stall     <= 1'b1;
          link_hold <= 1'b1;
          clr_req   <= 1'b1;
          rh        <= RH_ACK;
        end
        RH_ACK: begin
          stall     <= 1'b1;
          link_hold <= 1'b1;
          clr_req   <= 1'b1;
          if (ack2) begin
            clr_cnt <= 4'h0;
            rh      <= RH_HOLD;
          end
        end
        RH_HOLD: begin
          stall     <= 1'b1;
          link_hold <= 1'b1;
          clr_req   <= 1'b1;
          if (clr_cnt == 4'd8) begin
            rate_use <= rate_norm;
            clr_req  <= 1'b0;
            rh       <= RH_REL;
          end else begin
            clr_cnt <= clr_cnt + 4'd1;
          end
        end
        RH_REL: begin
          link_hold <= 1'b1;
          clr_req   <= 1'b0;
          if (!ack2) begin
            stall <= 1'b0;
            link_hold <= 1'b0;
            rh    <= RH_IDLE;
          end else begin
            stall <= 1'b1;
          end
        end
        default: begin
          stall     <= 1'b0;
          link_hold <= 1'b0;
          clr_req   <= 1'b0;
          rh        <= RH_IDLE;
        end
      endcase
    end
  end

  // xcode_en is a client-clock CSR bit. System block lock sees the packed
  // sync marker only after it has crossed into clk_system.
  always_ff @(posedge clk_system or negedge rst_system_n) begin
    if (!rst_system_n)
      xcode_meta <= 2'b00;
    else
      xcode_meta <= {xcode_meta[0], xcode_en};
  end

  fc_rx_front u_client_rx (
    .clk           (clk_client),
    .rst_n         (rst_client_n),
    .scrambler_en  (scrambler_en),
    .sync_relax    (1'b0),
    .valid         (client_rx_valid),
    .ready         (c_rx_ready),
    .sync_in       (client_rx_sync),
    .data_in       (client_rx_data),
    .sync_out      (c_rx_sync),
    .data_out      (c_rx_data),
    .locked        (client_lock)
  );
  assign client_rx_ready = c_rx_ready;

  fc_scrambler u_client_tx_scr (
    .clk        (clk_client),
    .rst_n      (rst_client_n),
    .en         (scrambler_en),
    .descramble (1'b0),
    .step       (c_tx_valid && client_tx_ready),
    .din        (c_tx_data),
    .dout       (client_tx_data)
  );
  assign client_tx_valid = c_tx_valid;
  assign client_tx_sync  = c_tx_sync;
  assign c_tx_ready      = client_tx_ready;

  fc_pipe #(.MAX_PAY(MAX_PAY)) u_c2s (
    .clk             (clk_client),
    .rst_n           (rst_client_n),
    .port_en         (port_en),
    .fec_en          (fec_en),
    .locked          (client_lock),
    .rx_link_up      (client_link_up),
    .tx_link_up      (system_link_up),
    .tx_os           (system_tx_os),
    .rx_valid        (client_rx_valid),
    .rx_ready        (c_rx_ready),
    .rx_sync         (c_rx_sync),
    .rx_data         (c_rx_data),
    .tx_valid        (c_tx_to_split_valid),
    .tx_ready        (rate_tx_ready),
    .tx_sync         (c_tx_to_split_sync),
    .tx_data         (c_tx_to_split_data),
    .credit_ok       (sys_cr != 8'h00),
    .credit_take     (c2s_take),
    .saw_r_rdy       (c2s_rrdy),
    .rrdy_req        (s2c_acc),
    .frame_accepted  (c2s_acc),
    .stat_rx_good    (c2s_rx),
    .stat_tx_frames  (c2s_tx),
    .stat_crc_err    (c2s_crc),
    .stat_fec_corr   (c2s_corr),
    .stat_fec_fail   (c2s_fail),
    .between_frames  (c2s_idle)
  );

  fc_rate_tx u_rate_tx (
    .clk       (clk_client),
    .rst_n     (rst_stream_n),
    .half      (half),
    .in_valid  (c_tx_to_split_valid),
    .in_ready  (rate_tx_ready),
    .in_sync   (c_tx_to_split_sync),
    .in_data   (c_tx_to_split_data),
    .out_valid (rate_tx_valid),
    .out_ready (x_in_ready),
    .out_sync  (rate_tx_sync),
    .out_data  (rate_tx_data)
  );

  fc_xcode_tx u_xcode_tx (
    .clk       (clk_client),
    .rst_n     (rst_stream_n),
    .en        (xcode_en),
    .in_valid  (rate_tx_valid),
    .in_ready  (x_in_ready),
    .in_sync   (rate_tx_sync),
    .in_data   (rate_tx_data),
    .out_valid (x_to_split_valid),
    .out_ready (rs_tx_ready),
    .out_sync  (x_to_split_sync),
    .out_data  (x_to_split_data)
  );

  // RS(544,514) rides the packed groups. It stays a wire unless the
  // 256b/257b transcode is on, because the trailer framing assumes those beats.
  fc_rs544_tx u_rs_tx (
    .clk       (clk_client),
    .rst_n     (rst_stream_n),
    .en        (rs544_en & xcode_en),
    .in_valid  (x_to_split_valid),
    .in_ready  (rs_tx_ready),
    .in_sync   (x_to_split_sync),
    .in_data   (x_to_split_data),
    .out_valid (rs_to_split_valid),
    .out_ready (split_ready),
    .out_sync  (rs_to_split_sync),
    .out_data  (rs_to_split_data)
  );

  fc_pair_split #(.DEPTH(FIFO_DEPTH)) u_split (
    .clk_wr   (clk_client),
    .rst_wr_n (rst_fifo_c_n),
    .clk_rd   (clk_system),
    .rst_rd_n (rst_fifo_s_n),
    .stripe   (stripe),
    .wr_valid (rs_to_split_valid),
    .wr_ready (split_ready),
    .wr_sync  (rs_to_split_sync),
    .wr_data  (rs_to_split_data),
    .rd_valid (split_valid),
    .rd_ready (sys_tx_ready),
    .rd_sync  (split_sync),
    .rd_data  (split_data)
  );

  genvar si;
  generate
    for (si = 0; si < 2; si = si + 1) begin : g_sys_tx
      fc_scrambler u_scr (
        .clk        (clk_system),
        .rst_n      (rst_system_n),
        .en         (scrambler_en_s),
        .descramble (1'b0),
        .step       (split_valid[si] && sys_tx_ready[si]),
        .din        (split_data[si]),
        .dout       (sys_tx_scr[si])
      );
      assign sys_tx_valid[si] = split_valid[si];
      assign sys_tx_sync[si]  = split_valid[si] ? split_sync[si] : 2'b00;
      assign sys_tx_data[si]  = split_valid[si] ? sys_tx_scr[si] : 64'h0;
    end
  endgenerate

  generate
    for (si = 0; si < 2; si = si + 1) begin : g_sys_rx
      fc_rx_front u_sys_rx (
        .clk           (clk_system),
        .rst_n         (rst_system_n),
        .scrambler_en  (scrambler_en_s),
        .sync_relax    (xcode_meta[1]),
        .valid         (sys_rx_valid[si]),
        .ready         (sys_rx_ready[si]),
        .sync_in       (sys_rx_sync[si]),
        .data_in       (sys_rx_data[si]),
        .sync_out      (sys_front_sync[si]),
        .data_out      (sys_front_data[si]),
        .locked        (sys_lock[si])
      );
    end
  endgenerate

  fc_pair_merge #(.DEPTH(FIFO_DEPTH)) u_merge (
    .clk_wr   (clk_system),
    .rst_wr_n (rst_fifo_s_n),
    .clk_rd   (clk_client),
    .rst_rd_n (rst_fifo_c_n),
    .stripe   (stripe),
    .wr_valid (sys_rx_valid),
    .wr_ready (sys_rx_ready),
    .wr_sync  (sys_front_sync),
    .wr_data  (sys_front_data),
    .rd_valid (merge_valid),
    .rd_ready (merge_ready),
    .rd_sync  (merge_sync),
    .rd_data  (merge_data)
  );

  fc_rs544_rx u_rs_rx (
    .clk        (clk_client),
    .rst_n      (rst_stream_n),
    .en         (rs544_en & xcode_en),
    .in_valid   (merge_valid),
    .in_ready   (merge_ready),
    .in_sync    (merge_sync),
    .in_data    (merge_data),
    .out_valid  (rs_rx_valid),
    .out_ready  (rs_rx_ready),
    .out_sync   (rs_rx_sync),
    .out_data   (rs_rx_data),
    .corr_pulse (rs_corr_pulse),
    .corr_nerr  (rs_corr_nerr),
    .fail_pulse (rs_fail_pulse)
  );

  fc_xcode_rx u_xcode_rx (
    .clk       (clk_client),
    .rst_n     (rst_stream_n),
    .en        (xcode_en),
    .in_valid  (rs_rx_valid),
    .in_ready  (rs_rx_ready),
    .in_sync   (rs_rx_sync),
    .in_data   (rs_rx_data),
    .out_valid (dec_valid),
    .out_ready (rate_rx_in_ready),
    .out_sync  (dec_sync),
    .out_data  (dec_data)
  );

  fc_rate_rx u_rate_rx (
    .clk       (clk_client),
    .rst_n     (rst_stream_n),
    .half      (half),
    .in_valid  (dec_valid),
    .in_ready  (rate_rx_in_ready),
    .in_sync   (dec_sync),
    .in_data   (dec_data),
    .out_valid (rate_rx_valid),
    .out_ready (rate_pipe_ready),
    .out_sync  (rate_rx_sync),
    .out_data  (rate_rx_data)
  );

  fc_pipe #(.MAX_PAY(MAX_PAY)) u_s2c (
    .clk             (clk_client),
    .rst_n           (rst_client_n),
    .port_en         (port_en),
    .fec_en          (fec_en),
    .locked          (sys_locked),
    .rx_link_up      (system_link_up),
    .tx_link_up      (client_link_up),
    .tx_os           (client_tx_os),
    .rx_valid        (rate_rx_valid),
    .rx_ready        (rate_pipe_ready),
    .rx_sync         (rate_rx_sync),
    .rx_data         (rate_rx_data),
    .tx_valid        (s_pipe_tx_valid),
    .tx_ready        (c_tx_ready),
    .tx_sync         (s_pipe_tx_sync),
    .tx_data         (s_pipe_tx_data),
    .credit_ok       (cli_cr != 8'h00),
    .credit_take     (s2c_take),
    .saw_r_rdy       (s2c_rrdy),
    .rrdy_req        (c2s_acc),
    .frame_accepted  (s2c_acc),
    .stat_rx_good    (s2c_rx),
    .stat_tx_frames  (s2c_tx),
    .stat_crc_err    (s2c_crc),
    .stat_fec_corr   (s2c_corr),
    .stat_fec_fail   (s2c_fail),
    .between_frames  (s2c_idle)
  );
  assign c_tx_valid = s_pipe_tx_valid;
  assign c_tx_sync  = s_pipe_tx_sync;
  assign c_tx_data  = s_pipe_tx_data;

  fc_link_sm u_client_link (
    .clk        (clk_client),
    .rst_n      (rst_client_n),
    .port_en    (port_en),
    .locked     (link_ok_c),
    .rx_fire    (client_rx_valid && c_rx_ready),
    .rx_sync    (c_rx_sync),
    .rx_data    (c_rx_data),
    .link_up    (client_link_up),
    .tx_os      (client_tx_os),
    .state_code (client_ls)
  );

  fc_link_sm u_system_link (
    .clk        (clk_client),
    .rst_n      (rst_client_n),
    .port_en    (port_en),
    .locked     (link_ok_s),
    .rx_fire    (rate_rx_valid && rate_pipe_ready),
    .rx_sync    (rate_rx_sync),
    .rx_data    (rate_rx_data),
    .link_up    (system_link_up),
    .tx_os      (system_tx_os),
    .state_code (system_ls)
  );

  always_comb begin
    cli_next = {1'b0, cli_cr};
    sys_next = {1'b0, sys_cr};
    if (s2c_take && cli_next != 9'h000)
      cli_next = cli_next - 9'd1;
    if (c2s_rrdy && cli_next != 9'h0FF)
      cli_next = cli_next + 9'd1;
    if (c2s_take && sys_next != 9'h000)
      sys_next = sys_next - 9'd1;
    if (s2c_rrdy && sys_next != 9'h0FF)
      sys_next = sys_next + 9'd1;
  end

  always_ff @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n) begin
      cli_cr <= 8'(DEFAULT_CREDIT);
      sys_cr <= 8'(DEFAULT_CREDIT);
    end else if (credit_load || credit_reload) begin
      cli_cr <= credit_cli_i;
      sys_cr <= credit_sys_i;
    end else begin
      cli_cr <= cli_next[7:0];
      sys_cr <= sys_next[7:0];
    end
  end

  always_ff @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n) begin
      rs544_corr <= '0;
      rs544_fail <= '0;
    end else begin
      if (rs_corr_pulse) begin
        if ({1'b0, rs544_corr} + {12'h0, rs_corr_nerr} > 17'h0FFFF)
          rs544_corr <= 16'hFFFF;
        else
          rs544_corr <= rs544_corr + {11'h0, rs_corr_nerr};
      end
      if (rs_fail_pulse && rs544_fail != 16'hFFFF)
        rs544_fail <= rs544_fail + 16'd1;
    end
  end

  assign credit_cli      = cli_cr;
  assign credit_sys      = sys_cr;
  assign stat_rx_frames  = c2s_rx;
  assign stat_tx_frames  = s2c_tx;
  assign stat_crc_err    = c2s_crc + s2c_crc;
  assign stat_fec_corr   = c2s_corr + s2c_corr;
  assign stat_fec_fail   = c2s_fail + s2c_fail;
  assign stat_rs544_corr = rs544_corr;
  assign stat_rs544_fail = rs544_fail;
endmodule
