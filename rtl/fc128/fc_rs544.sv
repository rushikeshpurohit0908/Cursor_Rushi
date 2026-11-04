// RS(544,514) codec over GF(2^10), polynomial x^10+x^3+1 (0x409).
// Generator roots are alpha^0..alpha^29, the FC-PI-8 / IEEE 802.3 Clause 91
// code. Shortened messages (1..514 symbols) are encoded directly and decoded
// over the transmitted length K+30. Symbol 0 is transmitted first.
//
// mem_rdata is combinational from mem_addr, same handshake as fc_rs_fec.
// The frame pipe keeps that 8-bit engine: its buffer is 256 bytes and a full
// codeword here is 544 ten-bit symbols. fc_rs544_stream is the stitch:
// twenty 257-bit transcoded blocks are the 514 message symbols.
module fc_rs544 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        encode,
  input  logic [9:0]  k_len,
  output logic        busy,
  output logic        done,
  output logic        fail,
  output logic [4:0]  nerr,

  output logic [9:0]  mem_addr,
  output logic        mem_we,
  output logic [9:0]  mem_wdata,
  input  logic [9:0]  mem_rdata
);
  `include "fc_rs544_tables.vh"

  function automatic [9:0] rs_exp(input integer idx);
    rs_exp = RS544_EXP_BITS[idx * 10 +: 10];
  endfunction

  function automatic [9:0] rs_log(input integer idx);
    rs_log = RS544_LOG_BITS[idx * 10 +: 10];
  endfunction

  function automatic [9:0] rs_gen(input integer idx);
    rs_gen = RS544_GEN_BITS[idx * 10 +: 10];
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
  logic [9:0]  k_r;
  logic [9:0]  nwords;
  logic [9:0]  idx;
  logic [9:0]  rem_p [0:29];
  logic [9:0]  syn   [0:29];
  logic [9:0]  lam   [0:30];
  logic [9:0]  bpoly [0:30];
  logic [4:0]  lam_deg;
  logic [5:0]  bm_m;
  logic [9:0]  bm_b;
  logic [4:0]  bm_n;
  logic [9:0]  epos  [0:14];
  logic [5:0]  ecount;
  logic [3:0]  eidx;
  logic [9:0]  omega [0:29];
  logic [9:0]  vsym  [0:29];
  logic        syn_nz;
  logic        apply_ok;

  integer gi;
  integer aj;

  function automatic [9:0] gf_mul(input [9:0] a, input [9:0] b);
    integer sum;
    begin
      if (a == 10'h000 || b == 10'h000)
        gf_mul = 10'h000;
      else begin
        sum    = rs_log(a) + rs_log(b);
        gf_mul = rs_exp(sum);
      end
    end
  endfunction

  function automatic [9:0] gf_div(input [9:0] a, input [9:0] b);
    integer diff;
    begin
      if (a == 10'h000)
        gf_div = 10'h000;
      else begin
        diff = rs_log(a) - rs_log(b);
        if (diff < 0)
          diff = diff + 1023;
        gf_div = rs_exp(diff);
      end
    end
  endfunction

  function automatic [9:0] gf_pow_neg(input integer power);
    integer modp;
    begin
      modp = power % 1023;
      if (modp == 0)
        gf_pow_neg = 10'h001;
      else
        gf_pow_neg = rs_exp(1023 - modp);
    end
  endfunction

  // Memory writes are combinational from the current state so the parent RAM
  // captures the same address and data on this clock edge.
  always_comb begin
    integer aoff;
    integer apower;
    reg [9:0] anum;
    reg [9:0] aden;
    reg [9:0] axp;
    reg [9:0] axinv;
    reg [9:0] xpos;
    mem_we    = 1'b0;
    mem_wdata = 10'h000;
    apply_ok  = 1'b0;
    if (state == S_ENC_OUT) begin
      aoff      = idx - k_r;
      mem_we    = 1'b1;
      mem_wdata = rem_p[29 - aoff];
    end else if (state == S_APPLY) begin
      // Roots start at alpha^0, so the magnitude is X * Omega(X^-1) / Lambda'.
      apower = nwords - 10'd1 - epos[eidx];
      axinv  = gf_pow_neg(apower);
      xpos   = rs_exp(apower);
      anum   = 10'h000;
      axp    = 10'h001;
      for (aj = 0; aj < 30; aj = aj + 1) begin
        anum = anum ^ gf_mul(omega[aj], axp);
        axp  = gf_mul(axp, axinv);
      end
      anum = gf_mul(anum, xpos);
      aden = 10'h000;
      axp  = 10'h001;
      for (aj = 1; aj <= 30; aj = aj + 2) begin
        if (aj <= lam_deg) begin
          aden = aden ^ gf_mul(lam[aj], axp);
          axp  = gf_mul(axp, gf_mul(axinv, axinv));
        end
      end
      if (aden != 10'h000) begin
        apply_ok  = 1'b1;
        mem_we    = 1'b1;
        mem_wdata = mem_rdata ^ gf_div(anum, aden);
      end
    end
  end

  always_comb begin
    syn_nz = 1'b0;
    for (gi = 0; gi < 30; gi = gi + 1)
      if (syn[gi] != 10'h000)
        syn_nz = 1'b1;
  end

  assign mem_addr = (state == S_APPLY) ? epos[eidx] : idx;

  always_ff @(posedge clk or negedge rst_n) begin
    integer j;
    integer n;
    reg [9:0] delta;
    reg [9:0] coef;
    reg [9:0] lam_n [0:30];
    reg [9:0] b_n   [0:30];
    reg [4:0] deg_n;
    reg [5:0] m_n;
    reg [9:0] bcoef_n;
    reg [9:0] acc;
    reg [9:0] xp;
    reg [9:0] xinv;
    reg [9:0] feedback;
    reg [9:0] new_rem [0:29];
    if (!rst_n) begin
      state   <= S_IDLE;
      busy    <= 1'b0;
      done    <= 1'b0;
      fail    <= 1'b0;
      nerr    <= '0;
      idx     <= '0;
      ecount  <= '0;
      eidx    <= '0;
      k_r     <= '0;
      nwords  <= '0;
      lam_deg <= '0;
      bm_m    <= 6'd1;
      bm_b    <= 10'h001;
      bm_n    <= '0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy <= 1'b1;
            fail <= 1'b0;
            nerr <= '0;
            idx  <= '0;
            k_r  <= k_len;
            if (k_len == 10'd0 || k_len > 10'd514) begin
              fail  <= 1'b1;
              state <= S_FINISH;
            end else if (encode) begin
              nwords <= k_len;
              for (j = 0; j < 30; j = j + 1)
                rem_p[j] <= 10'h000;
              state <= S_ENC;
            end else begin
              nwords <= k_len + 10'd30;
              for (j = 0; j < 30; j = j + 1)
                syn[j] <= 10'h000;
              state <= S_SYN;
            end
          end
        end

        S_ENC: begin
          feedback = mem_rdata ^ rem_p[29];
          new_rem[0] = gf_mul(feedback, rs_gen(0));
          for (j = 1; j < 30; j = j + 1)
            new_rem[j] = rem_p[j - 1] ^ gf_mul(feedback, rs_gen(j));
          for (j = 0; j < 30; j = j + 1)
            rem_p[j] <= new_rem[j];
          if (idx + 10'd1 == k_r) begin
            idx   <= k_r;
            state <= S_ENC_OUT;
          end else begin
            idx <= idx + 10'd1;
          end
        end

        S_ENC_OUT: begin
          j = idx - k_r;
          if (j == 29)
            state <= S_FINISH;
          else
            idx <= idx + 10'd1;
        end

        S_SYN: begin
          for (j = 0; j < 30; j = j + 1)
            syn[j] <= gf_mul(syn[j], rs_exp(j)) ^ mem_rdata;
          if (idx + 10'd1 == nwords)
            state <= S_SYN_DONE;
          else
            idx <= idx + 10'd1;
        end

        S_SYN_DONE: begin
          if (!syn_nz) begin
            nerr  <= '0;
            fail  <= 1'b0;
            state <= S_FINISH;
          end else begin
            for (j = 0; j <= 30; j = j + 1) begin
              lam[j]   <= (j == 0) ? 10'h001 : 10'h000;
              bpoly[j] <= (j == 0) ? 10'h001 : 10'h000;
            end
            lam_deg <= '0;
            bm_m    <= 6'd1;
            bm_b    <= 10'h001;
            bm_n    <= '0;
            state   <= S_BM;
          end
        end

        S_BM: begin
          n = bm_n;
          delta = syn[n];
          for (j = 1; j <= 30; j = j + 1) begin
            if (j <= lam_deg && j <= n)
              delta = delta ^ gf_mul(lam[j], syn[n - j]);
          end
          for (j = 0; j <= 30; j = j + 1) begin
            lam_n[j] = lam[j];
            b_n[j]   = bpoly[j];
          end
          deg_n   = lam_deg;
          m_n     = bm_m;
          bcoef_n = bm_b;
          if (delta == 10'h000) begin
            m_n = bm_m + 6'd1;
          end else if ({lam_deg, 1'b0} <= {1'b0, bm_n}) begin
            coef = gf_div(delta, bm_b);
            for (j = 0; j <= 30; j = j + 1) begin
              if (j >= bm_m)
                lam_n[j] = lam[j] ^ gf_mul(coef, bpoly[j - bm_m]);
            end
            deg_n   = (bm_n + 5'd1) - lam_deg;
            for (j = 0; j <= 30; j = j + 1)
              b_n[j] = lam[j];
            bcoef_n = delta;
            m_n     = 6'd1;
          end else begin
            coef = gf_div(delta, bm_b);
            for (j = 0; j <= 30; j = j + 1) begin
              if (j >= bm_m)
                lam_n[j] = lam[j] ^ gf_mul(coef, bpoly[j - bm_m]);
            end
            m_n = bm_m + 6'd1;
          end
          for (j = 0; j <= 30; j = j + 1) begin
            lam[j]   <= lam_n[j];
            bpoly[j] <= b_n[j];
          end
          lam_deg <= deg_n;
          bm_m    <= m_n;
          bm_b    <= bcoef_n;
          if (bm_n == 5'd29)
            state <= S_CHIEN;
          else
            bm_n <= bm_n + 5'd1;
          idx    <= '0;
          ecount <= '0;
        end

        S_CHIEN: begin
          xinv = gf_pow_neg(idx);
          acc  = 10'h000;
          xp   = 10'h001;
          for (j = 0; j <= 30; j = j + 1) begin
            if (j <= lam_deg) begin
              acc = acc ^ gf_mul(lam[j], xp);
              xp  = gf_mul(xp, xinv);
            end
          end
          if (acc == 10'h000) begin
            if (ecount < 6'd15)
              epos[ecount[3:0]] <= nwords - 10'd1 - idx;
            ecount <= ecount + 6'd1;
          end
          if (idx + 10'd1 == nwords)
            state <= S_FORNEY;
          else
            idx <= idx + 10'd1;
        end

        S_FORNEY: begin
          if (lam_deg == 5'd0 || lam_deg > 5'd15 || ecount != {1'b0, lam_deg}) begin
            fail  <= 1'b1;
            nerr  <= '0;
            state <= S_FINISH;
          end else begin
            for (n = 0; n < 30; n = n + 1) begin
              acc = 10'h000;
              for (j = 0; j <= 30; j = j + 1) begin
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
            nerr  <= ecount[4:0];
            eidx  <= '0;
            idx   <= '0;
            for (j = 0; j < 30; j = j + 1)
              vsym[j] <= 10'h000;
            state <= S_VERIFY;
          end else begin
            eidx <= eidx + 4'd1;
          end
        end

        S_VERIFY: begin
          for (j = 0; j < 30; j = j + 1)
            vsym[j] <= gf_mul(vsym[j], rs_exp(j)) ^ mem_rdata;
          if (idx + 10'd1 == nwords)
            state <= S_VER_DONE;
          else
            idx <= idx + 10'd1;
        end

        S_VER_DONE: begin
          acc = 10'h000;
          for (j = 0; j < 30; j = j + 1)
            if (vsym[j] != 10'h000)
              acc = 10'h001;
          fail <= acc[0];
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
