// Behavioral SFP112 module on the CMIS two-wire interface.
//
// Lower memory follows CMIS 5.0. Byte 0 is SFF-8024 identifier 20h
// (SFP/SFP+ with CMIS). Byte 26 bit 4 is LowPwrRequestSW, bit 6 is
// LowPwrAllowRequestHW, and bit 3 is the self-clearing SoftwareReset.
// Page 10h byte 130 bit 0 is OutputDisableTx for lane 1. Temperature is
// signed 1/256 C at bytes 14-15. Supply is unsigned 100 uV at bytes 16-17.
// The slave does not stretch SCL. sda_oe drives a zero on the open-drain pad.
module cmis_sfp_slave #(
  parameter int PWR_DLY = 40,
  parameter [7:0] TXDIS_INIT = 8'hA0
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        scl_i,
  input  logic        sda_i,
  output logic        sda_oe,
  input  logic        lpmode,
  input  logic        reset_n,
  input  logic        force_fault,
  input  logic [15:0] temp_s16,
  input  logic [15:0] vcc_u16,
  output logic [2:0]  mod_state,
  output logic [7:0]  txdis_byte,
  output logic        flag_state
);
  `include "fc_cmis.vh"

  localparam [2:0] S_IDLE = 3'd0;
  localparam [2:0] S_ADDR = 3'd1;
  localparam [2:0] S_ACK  = 3'd2;
  localparam [2:0] S_RX   = 3'd3;
  localparam [2:0] S_TX   = 3'd4;
  localparam [2:0] S_MACK = 3'd5;

  logic [7:0] mem [0:255];
  logic [7:0] p10 [0:255];
  logic [2:0] st;
  logic [7:0] sh;
  logic [3:0] bits;
  logic [7:0] ptr;
  logic       scl_q, sda_q;
  logic       reading;
  logic       expect_ptr;
  logic       mack;
  logic       flag_sc;
  logic       flag_clr;
  logic       sw_hit;
  logic       sw_resetting;
  logic       held;
  logic       raise_flag;
  logic [2:0] mod_state_q;
  logic [15:0] pwr_cnt;
  integer ii;

  wire start = scl_q && scl_i && sda_q && !sda_i;
  wire stop  = scl_q && scl_i && !sda_q && sda_i;
  wire rise  = !scl_q && scl_i;
  wire fall  = scl_q && !scl_i;
  wire lowpwr_s = mem[CMIS_CTL][4] | (mem[CMIS_CTL][6] & lpmode);
  wire int_deassert = !(flag_sc && !mem[31][0]);

  assign txdis_byte = p10[CMIS_TXDIS];
  assign flag_state = flag_sc;
  assign mod_state = force_fault ? CMIS_ST_FLT :
                     sw_resetting ? CMIS_ST_LOW : mod_state_q;

  task automatic load_tx;
    input [7:0] a;
    reg [7:0] b;
    begin
      b = peek(a);
      sh <= b;
      sda_oe <= ~b[7];
    end
  endtask

  function automatic [7:0] peek(input [7:0] a);
    begin
      if (a == 8'd3)
        peek = {4'b0, (force_fault ? CMIS_ST_FLT : (sw_resetting ? CMIS_ST_LOW : mod_state_q)), int_deassert};
      else if (a == 8'd8)
        peek = {7'b0, flag_sc};
      else if (a == 8'd14)
        peek = temp_s16[15:8];
      else if (a == 8'd15)
        peek = temp_s16[7:0];
      else if (a == 8'd16)
        peek = vcc_u16[15:8];
      else if (a == 8'd17)
        peek = vcc_u16[7:0];
      else if (a < 8'd128)
        peek = mem[a];
      else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE)
        peek = p10[a];
      else
        peek = 8'h00;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ii = 0; ii < 256; ii = ii + 1) begin
        mem[ii] <= 8'h00;
        p10[ii] <= 8'h00;
      end
      mem[0] <= CMIS_ID_SFP;
      mem[1] <= CMIS_REV50;
      mem[2] <= 8'h00;
      mem[CMIS_CTL] <= 8'h40;
      mem[31] <= 8'hFF;
      mem[CMIS_PAGE] <= 8'h00;
      p10[CMIS_TXDIS] <= TXDIS_INIT;
      st <= S_IDLE;
      sh <= 8'h00;
      bits <= 4'd0;
      ptr <= 8'h00;
      scl_q <= 1'b1;
      sda_q <= 1'b1;
      reading <= 1'b0;
      expect_ptr <= 1'b0;
      mack <= 1'b1;
      sda_oe <= 1'b0;
      flag_clr <= 1'b0;
      sw_hit <= 1'b0;
    end else begin
      scl_q <= scl_i;
      sda_q <= sda_i;
      flag_clr <= 1'b0;
      sw_hit <= 1'b0;
      if (!reset_n) begin
        st <= S_IDLE;
        sda_oe <= 1'b0;
        bits <= 4'd0;
      end else if (start && !sw_resetting) begin
        st <= S_ADDR;
        bits <= 4'd0;
        sh <= 8'h00;
        sda_oe <= 1'b0;
      end else if (start || stop) begin
        st <= S_IDLE;
        sda_oe <= 1'b0;
      end else begin
        case (st)
          S_ADDR, S_RX: begin
            if (rise) begin
              sh <= {sh[6:0], sda_i};
              bits <= bits + 4'd1;
            end else if (fall && bits == 4'd8) begin
              bits <= 4'd0;
              if (st == S_ADDR) begin
                if (sh[7:1] == CMIS_DEV) begin
                  reading <= sh[0];
                  if (!sh[0])
                    expect_ptr <= 1'b1;
                  st <= S_ACK;
                  sda_oe <= 1'b1;
                end else begin
                  st <= S_IDLE;
                  sda_oe <= 1'b0;
                end
              end else begin
                st <= S_ACK;
                sda_oe <= 1'b1;
                if (expect_ptr) begin
                  ptr <= sh;
                  expect_ptr <= 1'b0;
                end else if (ptr == CMIS_CTL) begin
                  mem[ptr] <= sh & 8'hF7;
                  if (sh[3])
                    sw_hit <= 1'b1;
                  ptr <= ptr + 8'd1;
                end else if (ptr < 8'd128) begin
                  mem[ptr] <= sh;
                  ptr <= ptr + 8'd1;
                end else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE) begin
                  p10[ptr] <= sh;
                  ptr <= ptr + 8'd1;
                end else begin
                  ptr <= ptr + 8'd1;
                end
              end
            end
          end
          S_ACK: begin
            sda_oe <= 1'b1;
            if (fall) begin
              if (reading && (bits == 4'd0)) begin
                load_tx(ptr);
                if (ptr == 8'd8)
                  flag_clr <= 1'b1;
                ptr <= ptr + 8'd1;
                bits <= 4'd0;
                st <= S_TX;
                reading <= 1'b0;
              end else begin
                sda_oe <= 1'b0;
                bits <= 4'd0;
                st <= S_RX;
              end
            end
          end
          S_TX: begin
            sda_oe <= ~sh[7];
            if (rise) begin
              bits <= bits + 4'd1;
            end else if (fall && bits == 4'd8) begin
              sda_oe <= 1'b0;
              bits <= 4'd0;
              st <= S_MACK;
            end else if (fall) begin
              sh <= {sh[6:0], 1'b0};
              bits <= bits;
            end
          end
          S_MACK: begin
            sda_oe <= 1'b0;
            if (rise)
              mack <= sda_i;
            else if (fall) begin
              if (!mack) begin
                load_tx(ptr);
                if (ptr == 8'd8)
                  flag_clr <= 1'b1;
                ptr <= ptr + 8'd1;
                bits <= 4'd0;
                st <= S_TX;
              end else begin
                st <= S_IDLE;
              end
            end
          end
          default: begin
            st <= S_IDLE;
            sda_oe <= 1'b0;
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mod_state_q <= CMIS_ST_LOW;
      flag_sc <= 1'b0;
      sw_resetting <= 1'b0;
      held <= 1'b0;
      pwr_cnt <= 16'd0;
    end else if (!reset_n) begin
      mod_state_q <= CMIS_ST_LOW;
      sw_resetting <= 1'b0;
      pwr_cnt <= 16'd0;
      held <= 1'b1;
    end else begin
      raise_flag = 1'b0;
      if (sw_hit) begin
        sw_resetting <= 1'b1;
        pwr_cnt <= PWR_DLY[15:0];
      end else if (sw_resetting) begin
        if (pwr_cnt == 16'd0) begin
          sw_resetting <= 1'b0;
          mod_state_q <= CMIS_ST_LOW;
          raise_flag = 1'b1;
        end else begin
          pwr_cnt <= pwr_cnt - 16'd1;
        end
      end else if (force_fault) begin
        mod_state_q <= CMIS_ST_FLT;
      end else if (held) begin
        held <= 1'b0;
        raise_flag = 1'b1;
        mod_state_q <= CMIS_ST_LOW;
      end else if (mod_state_q == CMIS_ST_FLT) begin
        mod_state_q <= CMIS_ST_LOW;
      end else begin
        case (mod_state_q)
          CMIS_ST_LOW: begin
            if (!lowpwr_s) begin
              mod_state_q <= CMIS_ST_UP;
              pwr_cnt <= PWR_DLY[15:0];
            end
          end
          CMIS_ST_UP: begin
            if (pwr_cnt == 16'd0) begin
              mod_state_q <= CMIS_ST_RDY;
              raise_flag = 1'b1;
            end else begin
              pwr_cnt <= pwr_cnt - 16'd1;
            end
          end
          CMIS_ST_RDY: begin
            if (lowpwr_s) begin
              mod_state_q <= CMIS_ST_DN;
              pwr_cnt <= PWR_DLY[15:0];
            end
          end
          CMIS_ST_DN: begin
            if (pwr_cnt == 16'd0) begin
              mod_state_q <= CMIS_ST_LOW;
              raise_flag = 1'b1;
            end else begin
              pwr_cnt <= pwr_cnt - 16'd1;
            end
          end
          default: mod_state_q <= CMIS_ST_LOW;
        endcase
      end
      if (raise_flag)
        flag_sc <= 1'b1;
      else if (flag_clr)
        flag_sc <= 1'b0;
    end
  end
endmodule
