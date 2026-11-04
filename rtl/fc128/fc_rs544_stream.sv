// RS(544,514) on the packed 256b/257b stream.
//
// Twenty 257-bit words are 514 ten-bit symbols. Symbol 0 bit 0 is bit 0 of
// word 0 (the first transmitted bit). The 30 parity symbols follow the group
// as five beats with sync 11: 300 bits, then 20 zeros. A packed group is
// sync {0, x[256]}, 10, 11, 10, so five sync-11 beats do not occur there.
//
// fc_rs544_tx starts on a group boundary. fc_rs544_rx keeps a sliding window
// of the last 80 data beats and locks when a trailer follows an aligned
// window, which drops the rx_front warmup substitution. After lock it counts
// 80 data beats plus five trailer beats and ignores trailer sync, so a
// corrected symbol can land in the trailer. Disabled, both sides are wires.
// The frame-pipe RS(255,239) engine is a different code and stays where it is.

module fc_rs544_tx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data
);
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  localparam [2:0] S_HUNT = 3'd0;
  localparam [2:0] S_CAP  = 3'd1;
  localparam [2:0] S_MSG  = 3'd2;
  localparam [2:0] S_ARM  = 3'd3;
  localparam [2:0] S_ENC  = 3'd4;
  localparam [2:0] S_TAIL = 3'd5;
  localparam [2:0] S_SEND = 3'd6;

  logic [2:0]  state;
  logic [65:0] beat_mem [0:84];
  logic [9:0]  ram [0:543];
  logic [6:0]  cap_i;
  logic [1:0]  grp_b;
  logic [4:0]  grp;
  logic [9:0]  sym_i;
  logic [2:0]  tail_i;
  logic [6:0]  send_i;
  logic        start;
  logic        enc_i;
  logic        busy;
  logic        done;
  logic        fail;
  logic [4:0]  nerr;
  logic [9:0]  mem_addr;
  logic        mem_we;
  logic [9:0]  mem_wdata;
  logic [9:0]  mem_rdata;
  logic        codec_rst_n;

  wire cap_phase = (state == S_HUNT) || (state == S_CAP);
  wire take = en && rst_n && in_valid && cap_phase;

  assign codec_rst_n = rst_n & en;
  assign in_ready  = (!rst_n) ? 1'b0 : (en ? cap_phase : out_ready);
  assign out_valid = (!rst_n) ? 1'b0 : (en ? (state == S_SEND) : in_valid);
  assign out_sync  = en ? beat_mem[send_i][65:64] : in_sync;
  assign out_data  = en ? beat_mem[send_i][63:0] : in_data;
  assign mem_rdata = ram[mem_addr];

  fc_rs544 u_codec (
    .clk(clk), .rst_n(codec_rst_n), .start(start), .encode(enc_i),
    .k_len(10'd514), .busy(busy), .done(done), .fail(fail), .nerr(nerr),
    .mem_addr(mem_addr), .mem_we(mem_we), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    integer b;
    integer flat;
    integer w;
    integer wb;
    reg [9:0]  bits;
    reg [9:0]  symv;
    reg [63:0] pd;
    reg [256:0] xw;
    reg        grp_ok;
    if (!rst_n || !en) begin
      state  <= S_HUNT;
      cap_i  <= '0;
      grp_b  <= '0;
      grp    <= '0;
      sym_i  <= '0;
      tail_i <= '0;
      send_i <= '0;
      start  <= 1'b0;
      enc_i  <= 1'b1;
    end else begin
      start <= 1'b0;
      case (state)
        S_HUNT: begin
          if (take && (in_sync[1] == 1'b0)) begin
            beat_mem[0] <= {in_sync, in_data};
            cap_i <= 7'd1;
            grp_b <= 2'd1;
            grp   <= '0;
            state <= S_CAP;
          end
        end

        S_CAP: begin
          if (take) begin
            grp_ok = (grp_b == 2'd0) ? (in_sync[1] == 1'b0) :
                     (grp_b == 2'd1) ? (in_sync == 2'b10) :
                     (grp_b == 2'd2) ? (in_sync == 2'b11) :
                                       (in_sync == 2'b10);
            if (!grp_ok) begin
              if (in_sync[1] == 1'b0) begin
                beat_mem[0] <= {in_sync, in_data};
                cap_i <= 7'd1;
                grp_b <= 2'd1;
                grp   <= '0;
              end else begin
                state <= S_HUNT;
              end
            end else begin
              beat_mem[cap_i] <= {in_sync, in_data};
              if (grp_b == 2'd3) begin
                if (grp == 5'd19) begin
                  sym_i <= '0;
                  state <= S_MSG;
                end else begin
                  grp   <= grp + 5'd1;
                  grp_b <= 2'd0;
                  cap_i <= cap_i + 7'd1;
                end
              end else begin
                grp_b <= grp_b + 2'd1;
                cap_i <= cap_i + 7'd1;
              end
            end
          end
        end

        S_MSG: begin
          bits = 10'h000;
          for (b = 0; b < 10; b = b + 1) begin
            flat = (sym_i * 10) + b;
            w    = flat / 257;
            wb   = flat % 257;
            xw   = fc_xcode_unpack(
              beat_mem[w*4][65:64], beat_mem[w*4][63:0],
              beat_mem[w*4+1][63:0], beat_mem[w*4+2][63:0],
              beat_mem[w*4+3][63:0]);
            bits[b] = xw[wb];
          end
          ram[sym_i] <= bits;
          if (sym_i == 10'd513) begin
            state <= S_ARM;
          end else begin
            sym_i <= sym_i + 10'd1;
          end
        end

        S_ARM: begin
          enc_i <= 1'b1;
          start <= 1'b1;
          state <= S_ENC;
        end

        S_ENC: begin
          if (done) begin
            tail_i <= '0;
            state  <= S_TAIL;
          end
        end

        S_TAIL: begin
          pd = 64'h0;
          for (b = 0; b < 64; b = b + 1) begin
            flat = (tail_i * 64) + b;
            if (flat < 300) begin
              symv = ram[10'd514 + (flat / 10)];
              pd[b] = symv[flat % 10];
            end
          end
          beat_mem[7'd80 + tail_i] <= {2'b11, pd};
          if (tail_i == 3'd4) begin
            send_i <= '0;
            state  <= S_SEND;
          end else begin
            tail_i <= tail_i + 3'd1;
          end
        end

        S_SEND: begin
          if (out_ready) begin
            if (send_i == 7'd84)
              state <= S_HUNT;
            else
              send_i <= send_i + 7'd1;
          end
        end

        default: state <= S_HUNT;
      endcase
      if (mem_we && (state != S_MSG))
        ram[mem_addr] <= mem_wdata;
    end
  end
endmodule

module fc_rs544_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data,
  output logic        corr_pulse,
  output logic [4:0]  corr_nerr,
  output logic        fail_pulse
);
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  localparam [3:0] S_SEEK    = 4'd0;
  localparam [3:0] S_FLUSH   = 4'd1;
  localparam [3:0] S_CHECK   = 4'd2;
  localparam [3:0] S_CAP     = 4'd3;
  localparam [3:0] S_ALIGN   = 4'd4;
  localparam [3:0] S_PTAIL   = 4'd5;
  localparam [3:0] S_MSG     = 4'd6;
  localparam [3:0] S_PAR     = 4'd7;
  localparam [3:0] S_ARM     = 4'd8;
  localparam [3:0] S_DEC     = 4'd9;
  localparam [3:0] S_REBUILD = 4'd10;
  localparam [3:0] S_SEND    = 4'd11;

  logic [3:0]  state;
  logic [65:0] beat_mem [0:84];
  logic [65:0] win [0:79];
  logic [65:0] hold [0:3];
  logic [65:0] pend;
  logic [65:0] pbeat;
  logic [9:0]  ram [0:543];
  logic [6:0]  wn;
  logic [2:0]  hn;
  logic [2:0]  flush_i;
  logic [6:0]  cap_i;
  logic [9:0]  sym_i;
  logic [4:0]  word_i;
  logic [6:0]  send_i;
  logic        locked;
  logic        start;
  logic        enc_i;
  logic        busy;
  logic        done;
  logic        fail;
  logic [4:0]  nerr;
  logic [9:0]  mem_addr;
  logic        mem_we;
  logic [9:0]  mem_wdata;
  logic [9:0]  mem_rdata;
  logic        codec_rst_n;

  wire cap_phase = (state == S_SEEK) || (state == S_CAP) || (state == S_PTAIL);
  wire take = en && rst_n && in_valid && cap_phase;

  assign codec_rst_n = rst_n & en;
  assign in_ready  = (!rst_n) ? 1'b0 : (en ? cap_phase : out_ready);
  assign out_valid = (!rst_n) ? 1'b0 : (en ? (state == S_SEND) : in_valid);
  assign out_sync  = en ? beat_mem[send_i][65:64] : in_sync;
  assign out_data  = en ? beat_mem[send_i][63:0] : in_data;
  assign mem_rdata = ram[mem_addr];

  function automatic logic frames_ok(input integer base_is_mem);
    integer g;
    reg ok;
    reg [1:0] s0, s1, s2, s3;
    begin
      ok = 1'b1;
      for (g = 0; g < 20; g = g + 1) begin
        if (base_is_mem) begin
          s0 = beat_mem[g*4][65:64];
          s1 = beat_mem[g*4+1][65:64];
          s2 = beat_mem[g*4+2][65:64];
          s3 = beat_mem[g*4+3][65:64];
        end else begin
          s0 = win[g*4][65:64];
          s1 = win[g*4+1][65:64];
          s2 = win[g*4+2][65:64];
          s3 = win[g*4+3][65:64];
        end
        if (!fc_xcode_frame(s0, s1, s2, s3))
          ok = 1'b0;
      end
      frames_ok = ok;
    end
  endfunction

  fc_rs544 u_codec (
    .clk(clk), .rst_n(codec_rst_n), .start(start), .encode(enc_i),
    .k_len(10'd514), .busy(busy), .done(done), .fail(fail), .nerr(nerr),
    .mem_addr(mem_addr), .mem_we(mem_we), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    integer b;
    integer k;
    integer flat;
    integer w;
    integer wb;
    integer pb;
    reg [9:0]   bits;
    reg [9:0]   symv;
    reg [65:0]  beat;
    reg [256:0] xw;
    reg [263:0] pk;
    if (!rst_n || !en) begin
      state      <= S_SEEK;
      wn         <= '0;
      hn         <= '0;
      flush_i    <= '0;
      cap_i      <= '0;
      sym_i      <= '0;
      word_i     <= '0;
      send_i     <= '0;
      locked     <= 1'b0;
      start      <= 1'b0;
      enc_i      <= 1'b0;
      corr_pulse <= 1'b0;
      corr_nerr  <= '0;
      fail_pulse <= 1'b0;
    end else begin
      start      <= 1'b0;
      corr_pulse <= 1'b0;
      fail_pulse <= 1'b0;
      case (state)
        S_SEEK: begin
          if (take) begin
            beat = {in_sync, in_data};
            if (beat[65:64] == 2'b11) begin
              if (hn < 3'd4) begin
                hold[hn] <= beat;
                hn <= hn + 3'd1;
              end else begin
                pbeat <= beat;
                state <= S_CHECK;
              end
            end else if (hn != 3'd0) begin
              pend    <= beat;
              flush_i <= '0;
              state   <= S_FLUSH;
            end else if (wn < 7'd80) begin
              win[wn] <= beat;
              wn <= wn + 7'd1;
            end else begin
              for (k = 0; k < 79; k = k + 1)
                win[k] <= win[k+1];
              win[79] <= beat;
            end
          end
        end

        S_FLUSH: begin
          if (flush_i < hn) begin
            beat = hold[flush_i];
            flush_i <= flush_i + 3'd1;
          end else begin
            beat = pend;
            hn <= '0;
            state <= S_SEEK;
          end
          if (wn < 7'd80) begin
            win[wn] <= beat;
            wn <= wn + 7'd1;
          end else begin
            for (k = 0; k < 79; k = k + 1)
              win[k] <= win[k+1];
            win[79] <= beat;
          end
        end

        S_CHECK: begin
          if ((wn == 7'd80) && frames_ok(0)) begin
            for (k = 0; k < 80; k = k + 1)
              beat_mem[k] <= win[k];
            beat_mem[80] <= hold[0];
            beat_mem[81] <= hold[1];
            beat_mem[82] <= hold[2];
            beat_mem[83] <= hold[3];
            beat_mem[84] <= pbeat;
            locked <= 1'b1;
            sym_i  <= '0;
            state  <= S_MSG;
          end else begin
            state <= S_SEEK;
          end
          wn <= '0;
          hn <= '0;
        end

        S_CAP: begin
          if (take) begin
            beat_mem[cap_i] <= {in_sync, in_data};
            if (cap_i == 7'd79) begin
              state <= S_ALIGN;
            end else begin
              cap_i <= cap_i + 7'd1;
            end
          end
        end

        S_ALIGN: begin
          if (!frames_ok(1)) begin
            locked <= 1'b0;
            wn     <= '0;
            hn     <= '0;
            state  <= S_SEEK;
          end else begin
            cap_i <= '0;
            state <= S_PTAIL;
          end
        end

        S_PTAIL: begin
          if (take) begin
            beat_mem[7'd80 + cap_i] <= {in_sync, in_data};
            if (cap_i == 7'd4) begin
              sym_i <= '0;
              state <= S_MSG;
            end else begin
              cap_i <= cap_i + 7'd1;
            end
          end
        end

        S_MSG: begin
          bits = 10'h000;
          for (b = 0; b < 10; b = b + 1) begin
            flat = (sym_i * 10) + b;
            w    = flat / 257;
            wb   = flat % 257;
            xw   = fc_xcode_unpack(
              beat_mem[w*4][65:64], beat_mem[w*4][63:0],
              beat_mem[w*4+1][63:0], beat_mem[w*4+2][63:0],
              beat_mem[w*4+3][63:0]);
            bits[b] = xw[wb];
          end
          ram[sym_i] <= bits;
          if (sym_i == 10'd513) begin
            sym_i <= '0;
            state <= S_PAR;
          end else begin
            sym_i <= sym_i + 10'd1;
          end
        end

        S_PAR: begin
          bits = 10'h000;
          for (b = 0; b < 10; b = b + 1) begin
            flat = (sym_i * 10) + b;
            pb   = 80 + (flat / 64);
            bits[b] = beat_mem[pb][flat % 64];
          end
          ram[10'd514 + sym_i] <= bits;
          if (sym_i == 10'd29) begin
            state <= S_ARM;
          end else begin
            sym_i <= sym_i + 10'd1;
          end
        end

        S_ARM: begin
          enc_i <= 1'b0;
          start <= 1'b1;
          state <= S_DEC;
        end

        S_DEC: begin
          if (done) begin
            if (fail) begin
              fail_pulse <= 1'b1;
              send_i <= '0;
              state  <= S_SEND;
            end else begin
              if (nerr != 5'd0) begin
                corr_pulse <= 1'b1;
                corr_nerr  <= nerr;
              end
              word_i <= '0;
              state  <= S_REBUILD;
            end
          end
        end

        S_REBUILD: begin
          xw = 257'h0;
          for (b = 0; b < 257; b = b + 1) begin
            flat = (word_i * 257) + b;
            symv = ram[flat / 10];
            xw[b] = symv[flat % 10];
          end
          pk = fc_xcode_pack(xw);
          beat_mem[word_i*4]     <= pk[65:0];
          beat_mem[word_i*4+1]   <= pk[131:66];
          beat_mem[word_i*4+2]   <= pk[197:132];
          beat_mem[word_i*4+3]   <= pk[263:198];
          if (word_i == 5'd19) begin
            send_i <= '0;
            state  <= S_SEND;
          end else begin
            word_i <= word_i + 5'd1;
          end
        end

        S_SEND: begin
          if (out_ready) begin
            if (send_i == 7'd79) begin
              if (locked) begin
                cap_i <= '0;
                state <= S_CAP;
              end else begin
                state <= S_SEEK;
              end
            end else begin
              send_i <= send_i + 7'd1;
            end
          end
        end

        default: state <= S_SEEK;
      endcase
      if (mem_we && (state != S_MSG) && (state != S_PAR))
        ram[mem_addr] <= mem_wdata;
    end
  end
endmodule
