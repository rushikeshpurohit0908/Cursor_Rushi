// RS(255,239) codec over GF(2^8), polynomial 0x11D, roots alpha^1..alpha^16.
// Shortened messages (1..239 data bytes) are encoded directly and decoded over
// the transmitted length K+16. This is the soft FEC block in the FC128 PoC.
// Production FC-PI-8 uses an RS(544,514)-class code; the start/done/RAM
// handshake is the drop-in point for that engine.
module fc_rs_fec (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       encode,
  input  logic [7:0] k_len,
  output logic       busy,
  output logic       done,
  output logic       fail,
  output logic [3:0] nerr,

  output logic [7:0] mem_addr,
  output logic       mem_we,
  output logic [7:0] mem_wdata,
  input  logic [7:0] mem_rdata
);
  `include "fc_rs_tables.vh"

  function automatic [7:0] rs_exp(input integer idx);
    rs_exp = RS_EXP_BITS[idx * 8 +: 8];
  endfunction

  function automatic [7:0] rs_log(input integer idx);
    rs_log = RS_LOG_BITS[idx * 8 +: 8];
  endfunction

  function automatic [7:0] rs_gen(input integer idx);
    rs_gen = RS_GEN_BITS[idx * 8 +: 8];
  endfunction

  localparam [3:0] S_IDLE     = 4'd0;
  localparam [3:0] S_ENC      = 4'd1;
  localparam [3:0] S_ENC_OUT  = 4'd2;
  localparam [3:0] S_SYN      = 4'd3;
  localparam [3:0] S_SYN_DONE = 4'd4;
  localparam [3:0] S_BM       = 4'd5;
  localparam [3:0] S_CHIEN    = 4'd6;
  localparam [3:0] S_FORNEY   = 4'd7;
  localparam [3:0] S_APPLY    = 4'd8;
  localparam [3:0] S_VERIFY   = 4'd9;
  localparam [3:0] S_VER_DONE = 4'd10;
  localparam [3:0] S_FINISH   = 4'd11;

  logic [3:0]  state;
  logic        enc_mode;
  logic [8:0]  k_r;
  logic [8:0]  nwords;
  logic [8:0]  idx;
  logic [7:0]  rem_p [0:15];
  logic [7:0]  syn   [0:15];
  logic [7:0]  lam   [0:16];
  logic [7:0]  bpoly [0:16];
  logic [4:0]  lam_deg;
  logic [4:0]  bm_m;
  logic [7:0]  bm_b;
  logic [4:0]  bm_n;
  logic [7:0]  epos  [0:7];
  logic [3:0]  ecount;
  logic [3:0]  eidx;
  logic [7:0]  omega [0:15];
  logic [7:0]  vsym  [0:15];
  logic        syn_nz;
  logic        apply_ok;

  integer gi;
  integer aj;

  // Memory writes are combinational from the current state so the parent RAM
  // captures the same address and data on this clock edge. Reads use mem_addr.
  always_comb begin
    integer aoff;
    integer apower;
    reg [7:0] anum;
    reg [7:0] aden;
    reg [7:0] axp;
    reg [7:0] axinv;
    mem_we     = 1'b0;
    mem_wdata  = 8'h00;
    apply_ok   = 1'b0;
    if (state == S_ENC_OUT) begin
      aoff      = idx - k_r;
      mem_we    = 1'b1;
      mem_wdata = rem_p[15 - aoff];
    end else if (state == S_APPLY) begin
      apower = nwords - 9'd1 - {1'b0, epos[eidx]};
      axinv  = gf_pow_neg(apower);
      anum   = 8'h00;
      axp    = 8'h01;
      for (aj = 0; aj < 16; aj = aj + 1) begin
        anum = anum ^ gf_mul(omega[aj], axp);
        axp  = gf_mul(axp, axinv);
      end
      aden = 8'h00;
      axp  = 8'h01;
      for (aj = 1; aj <= 16; aj = aj + 2) begin
        if (aj <= lam_deg) begin
          aden = aden ^ gf_mul(lam[aj], axp);
          axp  = gf_mul(axp, gf_mul(axinv, axinv));
        end
      end
      if (aden != 8'h00) begin
        apply_ok  = 1'b1;
        mem_we    = 1'b1;
        mem_wdata = mem_rdata ^ gf_div(anum, aden);
      end
    end
  end

  function automatic [7:0] gf_mul(input [7:0] a, input [7:0] b);
    integer sum;
    begin
      if (a == 8'h00 || b == 8'h00)
        gf_mul = 8'h00;
      else begin
        sum    = rs_log(a) + rs_log(b);
        gf_mul = rs_exp(sum);
      end
    end
  endfunction

  function automatic [7:0] gf_div(input [7:0] a, input [7:0] b);
    integer diff;
    begin
      if (a == 8'h00)
        gf_div = 8'h00;
      else begin
        diff = rs_log(a) - rs_log(b);
        if (diff < 0)
          diff = diff + 255;
        gf_div = rs_exp(diff);
      end
    end
  endfunction

  function automatic [7:0] gf_pow_neg(input integer power);
    integer modp;
    begin
      modp = power % 255;
      if (modp == 0)
        gf_pow_neg = 8'h01;
      else
        gf_pow_neg = rs_exp(255 - modp);
    end
  endfunction

  always_comb begin
    syn_nz = 1'b0;
    for (gi = 0; gi < 16; gi = gi + 1)
      if (syn[gi] != 8'h00)
        syn_nz = 1'b1;
  end

  // APPLY corrects one stored symbol per cycle, so the RAM port points at the
  // error locator that cycle. Every other state streams linearly through idx.
  assign mem_addr = (state == S_APPLY) ? epos[eidx] : idx[7:0];

  always_ff @(posedge clk or negedge rst_n) begin
    integer j;
    integer n;
    integer jj;
    reg [7:0] delta;
    reg [7:0] coef;
    reg [7:0] lam_n [0:16];
    reg [7:0] b_n   [0:16];
    reg [4:0] deg_n;
    reg [4:0] m_n;
    reg [7:0] bcoef_n;
    reg [7:0] acc;
    reg [7:0] xp;
    reg [7:0] xinv;
    reg [7:0] num;
    reg [7:0] den;
    reg [7:0] feedback;
    reg [7:0] new_rem [0:15];
    reg [8:0] power;
    if (!rst_n) begin
      state    <= S_IDLE;
      busy     <= 1'b0;
      done     <= 1'b0;
      fail     <= 1'b0;
      nerr     <= '0;
      idx      <= '0;
      ecount   <= '0;
      eidx     <= '0;
      enc_mode <= 1'b0;
      k_r      <= '0;
      nwords   <= '0;
      lam_deg  <= '0;
      bm_m     <= 5'd1;
      bm_b     <= 8'h01;
      bm_n     <= '0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy     <= 1'b1;
            fail     <= 1'b0;
            nerr     <= '0;
            enc_mode <= encode;
            k_r      <= {1'b0, k_len};
            idx      <= '0;
            if (encode) begin
              nwords <= {1'b0, k_len};
              for (j = 0; j < 16; j = j + 1)
                rem_p[j] <= 8'h00;
              state <= S_ENC;
            end else begin
              nwords <= {1'b0, k_len} + 9'd16;
              for (j = 0; j < 16; j = j + 1)
                syn[j] <= 8'h00;
              state <= S_SYN;
            end
          end
        end

        S_ENC: begin
          // High-first LFSR. rem_p[15] is the current x^15 coefficient.
          feedback = mem_rdata ^ rem_p[15];
          new_rem[0] = gf_mul(feedback, rs_gen(0));
          for (j = 1; j < 16; j = j + 1)
            new_rem[j] = rem_p[j-1] ^ gf_mul(feedback, rs_gen(j));
          for (j = 0; j < 16; j = j + 1)
            rem_p[j] <= new_rem[j];
          if (idx + 9'd1 == {1'b0, k_r[7:0]}) begin
            idx   <= {1'b0, k_r[7:0]};
            state <= S_ENC_OUT;
          end else begin
            idx <= idx + 9'd1;
          end
        end

        S_ENC_OUT: begin
          // Parity bytes are written by the comb RAM port. idx walks k..k+15.
          j = idx - k_r;
          if (j == 15)
            state <= S_FINISH;
          else
            idx <= idx + 9'd1;
        end

        S_SYN: begin
          for (j = 0; j < 16; j = j + 1)
            syn[j] <= gf_mul(syn[j], rs_exp(j + 1)) ^ mem_rdata;
          if (idx + 9'd1 == nwords) begin
            state <= S_SYN_DONE;
          end else begin
            idx <= idx + 9'd1;
          end
        end

        S_SYN_DONE: begin
          if (!syn_nz) begin
            nerr  <= '0;
            fail  <= 1'b0;
            state <= S_FINISH;
          end else begin
            for (j = 0; j <= 16; j = j + 1) begin
              lam[j]   <= (j == 0) ? 8'h01 : 8'h00;
              bpoly[j] <= (j == 0) ? 8'h01 : 8'h00;
            end
            lam_deg <= '0;
            bm_m    <= 5'd1;
            bm_b    <= 8'h01;
            bm_n    <= '0;
            state   <= S_BM;
          end
        end

        S_BM: begin
          n = bm_n;
          delta = syn[n];
          for (j = 1; j <= 16; j = j + 1) begin
            if (j <= lam_deg && j <= n)
              delta = delta ^ gf_mul(lam[j], syn[n - j]);
          end
          for (j = 0; j <= 16; j = j + 1) begin
            lam_n[j] = lam[j];
            b_n[j]   = bpoly[j];
          end
          deg_n   = lam_deg;
          m_n     = bm_m;
          bcoef_n = bm_b;
          if (delta == 8'h00) begin
            m_n = bm_m + 5'd1;
          end else if ({lam_deg, 1'b0} <= {1'b0, bm_n}) begin
            coef = gf_div(delta, bm_b);
            for (j = 0; j <= 16; j = j + 1) begin
              if (j >= bm_m)
                lam_n[j] = lam[j] ^ gf_mul(coef, bpoly[j - bm_m]);
            end
            deg_n   = (bm_n + 5'd1) - lam_deg;
            for (j = 0; j <= 16; j = j + 1)
              b_n[j] = lam[j];
            bcoef_n = delta;
            m_n     = 5'd1;
          end else begin
            coef = gf_div(delta, bm_b);
            for (j = 0; j <= 16; j = j + 1) begin
              if (j >= bm_m)
                lam_n[j] = lam[j] ^ gf_mul(coef, bpoly[j - bm_m]);
            end
            m_n = bm_m + 5'd1;
          end
          for (j = 0; j <= 16; j = j + 1) begin
            lam[j]   <= lam_n[j];
            bpoly[j] <= b_n[j];
          end
          lam_deg <= deg_n;
          bm_m    <= m_n;
          bm_b    <= bcoef_n;
          if (bm_n == 5'd15)
            state <= S_CHIEN;
          else
            bm_n <= bm_n + 5'd1;
          idx    <= '0;
          ecount <= '0;
        end

        S_CHIEN: begin
          power = idx;
          xinv  = gf_pow_neg(power);
          acc   = 8'h00;
          xp    = 8'h01;
          for (j = 0; j <= 16; j = j + 1) begin
            if (j <= lam_deg) begin
              acc = acc ^ gf_mul(lam[j], xp);
              xp  = gf_mul(xp, xinv);
            end
          end
          if (acc == 8'h00 && ecount < 4'd8) begin
            epos[ecount] <= nwords[7:0] - 8'd1 - idx[7:0];
            ecount       <= ecount + 4'd1;
          end
          if (idx + 9'd1 == nwords)
            state <= S_FORNEY;
          else
            idx <= idx + 9'd1;
        end

        S_FORNEY: begin
          if (lam_deg == 5'd0 || lam_deg > 5'd8 || {1'b0, ecount} != lam_deg) begin
            fail  <= 1'b1;
            nerr  <= '0;
            state <= S_FINISH;
          end else begin
            for (n = 0; n < 16; n = n + 1) begin
              acc = 8'h00;
              for (j = 0; j <= 16; j = j + 1) begin
                if (j <= n && j <= lam_deg)
                  acc = acc ^ gf_mul(lam[j], syn[n - j]);
              end
              omega[n] <= acc;
            end
            eidx  <= '0;
            state <= S_APPLY;
          end
        end

        S_APPLY: begin
          if (!apply_ok) begin
            fail  <= 1'b1;
            nerr  <= '0;
            state <= S_FINISH;
          end else if (eidx + 4'd1 == ecount) begin
            nerr  <= ecount;
            eidx  <= '0;
            idx   <= '0;
            for (j = 0; j < 16; j = j + 1)
              vsym[j] <= 8'h00;
            state <= S_VERIFY;
          end else begin
            eidx <= eidx + 4'd1;
          end
        end

        S_VERIFY: begin
          for (j = 0; j < 16; j = j + 1)
            vsym[j] <= gf_mul(vsym[j], rs_exp(j + 1)) ^ mem_rdata;
          if (idx + 9'd1 == nwords)
            state <= S_VER_DONE;
          else
            idx <= idx + 9'd1;
        end

        S_VER_DONE: begin
          acc = 8'h00;
          for (j = 0; j < 16; j = j + 1)
            if (vsym[j] != 8'h00)
              acc = 8'h01;
          fail  <= acc[0];
          if (acc[0])
            nerr <= '0;
          state <= S_FINISH;
        end

        S_FINISH: begin
          if (fail)
            nerr <= '0;
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
