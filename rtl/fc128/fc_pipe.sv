// One direction of the bridge: block stream in, frame buffer, optional RS-FEC,
// block stream out. Credit and R_RDY are sidebands so the parent can cross
// them between the client link and the system link.
//
// rx_link_up gates frame accept on this pipe's ingress. tx_link_up gates
// frame and R_RDY transmit; until then the pipe sources tx_os (the FC-FS
// primitive for NOS/OLS/LR/LRR/Idle).
module fc_pipe #(
  parameter int MAX_PAY = 128
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        port_en,
  input  logic        fec_en,
  input  logic        locked,
  input  logic        rx_link_up,
  input  logic        tx_link_up,
  input  logic [31:0] tx_os,

  input  logic        rx_valid,
  output logic        rx_ready,
  input  logic [1:0]  rx_sync,
  input  logic [63:0] rx_data,

  output logic        tx_valid,
  input  logic        tx_ready,
  output logic [1:0]  tx_sync,
  output logic [63:0] tx_data,

  input  logic        credit_ok,
  output logic        credit_take,
  output logic        saw_r_rdy,
  input  logic        rrdy_req,
  output logic        frame_accepted,

  output logic [31:0] stat_rx_good,
  output logic [31:0] stat_tx_frames,
  output logic [31:0] stat_crc_err,
  output logic [31:0] stat_fec_corr,
  output logic [31:0] stat_fec_fail,
  output logic        between_frames
);
  `include "fc128_defs.vh"
  `include "fc_crc.vh"

  localparam [2:0] RX_IDLE    = 3'd0;
  localparam [2:0] RX_FRM     = 3'd1;
  localparam [2:0] RX_BYTE    = 3'd2;
  localparam [2:0] RX_DROP    = 3'd3;
  localparam [2:0] RX_FEC_ARM = 3'd4;
  localparam [2:0] RX_FEC_GO  = 3'd5;
  localparam [2:0] RX_FEC_WAIT= 3'd6;
  localparam [2:0] RX_CRC     = 3'd7;

  localparam [2:0] TS_FLOW = 3'd0;
  localparam [2:0] TS_RRDY = 3'd1;
  localparam [2:0] TS_SOF  = 3'd2;
  localparam [2:0] TS_PACK = 3'd3;
  localparam [2:0] TS_DATA = 3'd4;
  localparam [2:0] TS_EOF  = 3'd5;

  logic [7:0] mem [0:255];
  integer mi;
  initial begin
    for (mi = 0; mi < 256; mi = mi + 1)
      mem[mi] = 8'h00;
  end

  logic [2:0]  rx_state;
  logic [2:0]  tx_state;
  logic [7:0]  k_len;
  logic [7:0]  wire_len;
  logic [7:0]  idx;
  logic [63:0] lat_data;
  logic [3:0]  lat_i;
  logic [31:0] eof_crc;
  logic [31:0] crc;
  logic [7:0]  crc_i;
  logic        use_fec;
  logic        pending;
  logic        pend_fec;
  logic [7:0]  pend_len;
  logic [31:0] pend_crc;
  logic [7:0]  tx_wire;
  logic [7:0]  tx_idx;
  logic [63:0] pack;
  logic [3:0]  pack_n;
  logic        in_frame;
  logic        enc_done;
  logic        enc_armed;
  logic        enc_started;
  logic        fec_start;
  logic        fec_encode;
  logic [7:0]  fec_k_r;
  logic        fec_busy;
  logic        fec_done;
  logic        fec_fail;
  logic [3:0]  fec_nerr;
  logic        fec_we;
  logic [7:0]  fec_addr;
  logic [7:0]  fec_wdata;
  logic [7:0]  fec_rdata;
  logic [7:0]  mem_raddr;
  logic [7:0]  rrdy_owed;
  logic        tx_fire;

  wire [2:0] lat_sel = lat_i[2:0];
  wire       byte_we = port_en && (rx_state == RX_BYTE) && (idx < wire_len) && (lat_i < 4'd8);
  wire [7:0] byte_wr = lat_data[lat_sel*8 +: 8];

  assign tx_fire = tx_valid && tx_ready;
  // True when this direction is not inside a frame, so a rate change can
  // reset the gearbox without cutting a SOF/payload/EOF on this pipe.
  assign between_frames = !in_frame && (rx_state == RX_IDLE) && (tx_state == TS_FLOW);
  assign rx_ready = port_en && (
    !locked ||
    (rx_state == RX_FRM) ||
    (rx_state == RX_DROP) ||
    ((rx_state == RX_IDLE) && !pending)
  );

  always_comb begin
    if (fec_busy)
      mem_raddr = fec_addr;
    else if (rx_state == RX_CRC)
      mem_raddr = crc_i;
    else
      mem_raddr = tx_idx;
  end
  assign fec_rdata = mem[mem_raddr];

  // Synchronous RAM. Reset is not on this sensitivity list: an async reset
  // edge with no reset clause is a write, and it blocks RAM inference.
  always_ff @(posedge clk) begin
    if (fec_we)
      mem[fec_addr] <= fec_wdata;
    else if (byte_we)
      mem[idx] <= byte_wr;
  end

  fc_rs_fec u_fec (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (fec_start),
    .encode    (fec_encode),
    .k_len     (fec_k_r),
    .busy      (fec_busy),
    .done      (fec_done),
    .fail      (fec_fail),
    .nerr      (fec_nerr),
    .mem_addr  (fec_addr),
    .mem_we    (fec_we),
    .mem_wdata (fec_wdata),
    .mem_rdata (fec_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    reg [7:0] owed_v;
    reg       send_rrdy;
    if (!rst_n) begin
      rx_state        <= RX_IDLE;
      tx_state        <= TS_FLOW;
      tx_valid        <= 1'b0;
      tx_sync         <= FC_SYNC_CTRL;
      tx_data         <= {32'h0, FC_IDLE};
      pending         <= 1'b0;
      in_frame        <= 1'b0;
      enc_done        <= 1'b0;
      enc_armed       <= 1'b0;
      enc_started     <= 1'b0;
      fec_start       <= 1'b0;
      fec_encode      <= 1'b0;
      fec_k_r         <= 8'h00;
      rrdy_owed       <= 8'h00;
      credit_take     <= 1'b0;
      saw_r_rdy       <= 1'b0;
      frame_accepted  <= 1'b0;
      stat_rx_good    <= 32'h0;
      stat_tx_frames  <= 32'h0;
      stat_crc_err    <= 32'h0;
      stat_fec_corr   <= 32'h0;
      stat_fec_fail   <= 32'h0;
      k_len           <= 8'h00;
      wire_len        <= 8'h00;
      idx             <= 8'h00;
      lat_i           <= 4'h0;
      crc             <= 32'hFFFF_FFFF;
      crc_i           <= 8'h00;
      use_fec         <= 1'b0;
      pack            <= 64'h0;
      pack_n          <= 4'h0;
      tx_idx          <= 8'h00;
      tx_wire         <= 8'h00;
      pend_len        <= 8'h00;
      pend_crc        <= 32'h0;
      pend_fec        <= 1'b0;
      eof_crc         <= 32'h0;
      lat_data        <= 64'h0;
    end else begin
      credit_take    <= 1'b0;
      saw_r_rdy      <= 1'b0;
      frame_accepted <= 1'b0;
      fec_start      <= 1'b0;

      owed_v = rrdy_owed;
      if (rrdy_req && owed_v != 8'hFF)
        owed_v = owed_v + 8'd1;
      send_rrdy = 1'b0;

      if (!port_en) begin
        rx_state    <= RX_IDLE;
        tx_state    <= TS_FLOW;
        tx_valid    <= 1'b0;
        pending     <= 1'b0;
        in_frame    <= 1'b0;
        enc_armed   <= 1'b0;
        enc_started <= 1'b0;
      end else begin
        // A lost block lock aborts a partial receive. A frame that already
        // passed CRC (pending) is kept so transmit can finish after recovery.
        if (!locked) begin
          rx_state <= RX_IDLE;
        end else begin
        case (rx_state)
          RX_IDLE: begin
            if (rx_valid && rx_ready && locked && !pending) begin
              if (rx_sync == FC_SYNC_CTRL && fc_is_sof(rx_data[31:0]) && rx_link_up) begin
                if (rx_data[47:32] >= 16'd1 && rx_data[47:32] <= MAX_PAY) begin
                  k_len    <= rx_data[39:32];
                  use_fec  <= fec_en;
                  wire_len <= fec_en ? (rx_data[39:32] + 8'd16) : rx_data[39:32];
                  idx      <= 8'h00;
                  rx_state <= RX_FRM;
                end else begin
                  rx_state <= RX_DROP;
                end
              end else if (rx_sync == FC_SYNC_CTRL && rx_data[31:0] == FC_RRDY && rx_link_up) begin
                saw_r_rdy <= 1'b1;
              end
            end
          end

          RX_FRM: begin
            if (rx_valid && rx_ready) begin
              if (rx_sync == FC_SYNC_DATA) begin
                lat_data <= rx_data;
                lat_i    <= 4'h0;
                rx_state <= RX_BYTE;
              end else if (rx_sync == FC_SYNC_CTRL && fc_is_eof_bad(rx_data[31:0])) begin
                stat_crc_err   <= stat_crc_err + 32'd1;
                frame_accepted <= 1'b1;
                rx_state       <= RX_IDLE;
              end else if (rx_sync == FC_SYNC_CTRL && fc_is_eof_good(rx_data[31:0])) begin
                eof_crc <= rx_data[63:32];
                if (idx != wire_len) begin
                  stat_crc_err   <= stat_crc_err + 32'd1;
                  frame_accepted <= 1'b1;
                  rx_state       <= RX_IDLE;
                end else if (use_fec) begin
                  rx_state <= RX_FEC_ARM;
                end else begin
                  crc      <= 32'hFFFF_FFFF;
                  crc_i    <= 8'h00;
                  rx_state <= RX_CRC;
                end
              end else begin
                rx_state <= RX_DROP;
              end
            end
          end

          RX_BYTE: begin
            if (idx >= wire_len || lat_i >= 4'd8) begin
              rx_state <= RX_FRM;
            end else begin
              idx   <= idx + 8'd1;
              lat_i <= lat_i + 4'd1;
            end
          end

          RX_DROP: begin
            if (rx_valid && rx_ready && rx_sync == FC_SYNC_CTRL &&
                (fc_is_eof_good(rx_data[31:0]) || fc_is_eof_bad(rx_data[31:0]))) begin
              stat_crc_err   <= stat_crc_err + 32'd1;
              frame_accepted <= 1'b1;
              rx_state       <= RX_IDLE;
            end
          end

          RX_FEC_ARM: begin
            fec_encode <= 1'b0;
            fec_k_r    <= k_len;
            rx_state   <= RX_FEC_GO;
          end

          RX_FEC_GO: begin
            rx_state <= RX_FEC_WAIT;
          end

          RX_FEC_WAIT: begin
            if (fec_done) begin
              if (fec_fail) begin
                stat_fec_fail  <= stat_fec_fail + 32'd1;
                frame_accepted <= 1'b1;
                rx_state       <= RX_IDLE;
              end else begin
                stat_fec_corr <= stat_fec_corr + {28'h0, fec_nerr};
                crc           <= 32'hFFFF_FFFF;
                crc_i         <= 8'h00;
                rx_state      <= RX_CRC;
              end
            end
          end

          RX_CRC: begin
            if (crc_i < k_len) begin
              crc   <= crc32_update(crc, fec_rdata);
              crc_i <= crc_i + 8'd1;
            end else if (~crc == eof_crc) begin
              pending        <= 1'b1;
              pend_len       <= k_len;
              pend_crc       <= ~crc;
              pend_fec       <= use_fec;
              tx_wire        <= use_fec ? (k_len + 8'd16) : k_len;
              enc_done       <= ~use_fec;
              enc_armed      <= 1'b0;
              enc_started    <= 1'b0;
              stat_rx_good   <= stat_rx_good + 32'd1;
              frame_accepted <= 1'b1;
              rx_state       <= RX_IDLE;
            end else begin
              stat_crc_err   <= stat_crc_err + 32'd1;
              frame_accepted <= 1'b1;
              rx_state       <= RX_IDLE;
            end
          end

          default: rx_state <= RX_IDLE;
        endcase
        end

        case (tx_state)
          TS_FLOW: begin
            if (!tx_valid || tx_fire) begin
              if (!tx_link_up && !in_frame) begin
                tx_valid <= 1'b1;
                tx_sync  <= FC_SYNC_CTRL;
                tx_data  <= {32'h0, tx_os};
                tx_state <= TS_FLOW;
              end else if (owed_v != 8'h00 && !in_frame) begin
                tx_valid  <= 1'b1;
                tx_sync   <= FC_SYNC_CTRL;
                tx_data   <= {32'h0, FC_RRDY};
                tx_state  <= TS_RRDY;
                send_rrdy  = 1'b1;
              end else if (pending && enc_done && credit_ok && !in_frame) begin
                tx_valid  <= 1'b1;
                tx_sync   <= FC_SYNC_CTRL;
                tx_data   <= {16'h0, 8'h00, pend_len, FC_SOF};
                tx_state  <= TS_SOF;
                in_frame  <= 1'b1;
              end else begin
                tx_valid <= 1'b1;
                tx_sync  <= FC_SYNC_CTRL;
                tx_data  <= {32'h0, FC_IDLE};
              end
            end
          end

          TS_RRDY: begin
            tx_valid <= 1'b1;
            tx_sync  <= FC_SYNC_CTRL;
            tx_data  <= {32'h0, FC_RRDY};
            if (tx_fire)
              tx_state <= TS_FLOW;
          end

          TS_SOF: begin
            tx_valid <= 1'b1;
            tx_sync  <= FC_SYNC_CTRL;
            tx_data  <= {16'h0, 8'h00, pend_len, FC_SOF};
            if (tx_fire) begin
              credit_take <= 1'b1;
              tx_state    <= TS_PACK;
              pack        <= 64'h0;
              pack_n      <= 4'h0;
              tx_idx      <= 8'h00;
              tx_valid    <= 1'b0;
            end
          end

          TS_PACK: begin
            tx_valid <= 1'b0;
            if (pack_n == 4'd8 || tx_idx == tx_wire) begin
              tx_state <= TS_DATA;
              tx_valid <= 1'b1;
              tx_sync  <= FC_SYNC_DATA;
              tx_data  <= pack;
            end else begin
              pack[pack_n*8 +: 8] <= fec_rdata;
              pack_n              <= pack_n + 4'd1;
              tx_idx              <= tx_idx + 8'd1;
            end
          end

          TS_DATA: begin
            tx_valid <= 1'b1;
            tx_sync  <= FC_SYNC_DATA;
            tx_data  <= pack;
            if (tx_fire) begin
              if (tx_idx == tx_wire) begin
                tx_state <= TS_EOF;
                tx_valid <= 1'b1;
                tx_sync  <= FC_SYNC_CTRL;
                tx_data  <= {pend_crc, FC_EOF};
              end else begin
                tx_state <= TS_PACK;
                pack     <= 64'h0;
                pack_n   <= 4'h0;
                tx_valid <= 1'b0;
              end
            end
          end

          TS_EOF: begin
            tx_valid <= 1'b1;
            tx_sync  <= FC_SYNC_CTRL;
            tx_data  <= {pend_crc, FC_EOF};
            if (tx_fire) begin
              pending        <= 1'b0;
              in_frame       <= 1'b0;
              stat_tx_frames <= stat_tx_frames + 32'd1;
              tx_state       <= TS_FLOW;
              tx_valid       <= 1'b1;
              tx_sync        <= FC_SYNC_CTRL;
              tx_data        <= {32'h0, FC_IDLE};
            end
          end

          default: tx_state <= TS_FLOW;
        endcase

        if (locked && rx_state == RX_FEC_GO)
          fec_start <= 1'b1;
        else if (enc_armed && !enc_started) begin
          fec_start   <= 1'b1;
          enc_started <= 1'b1;
        end else if (pending && pend_fec && !enc_done && !enc_armed &&
                     rx_state == RX_IDLE && !fec_busy) begin
          fec_encode <= 1'b1;
          fec_k_r    <= pend_len;
          enc_armed  <= 1'b1;
        end

        if (enc_started && !enc_done && fec_done)
          enc_done <= 1'b1;
      end

      if (send_rrdy && owed_v != 8'h00)
        owed_v = owed_v - 8'd1;
      rrdy_owed <= owed_v;
    end
  end
endmodule
