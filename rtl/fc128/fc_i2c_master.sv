// Open-drain I2C master for one CMIS management interface.
//
// scl_oe and sda_oe are active-high drive-low. A released line is a 1
// through the board pull-up. The master waits while scl_i stays low, so a
// module may stretch the clock.
//
// cmd_valid is a one-cycle request, issued only while cmd_ready is high.
// cmd_write moves one byte. A clear cmd_write is a random read of cmd_rlen
// bytes (1..32) from cmd_addr. Device address is the 7-bit CMIS address.
// Each read byte is pulsed on rx_valid. cmd_done pulses after STOP.
// cmd_nack means the module did not acknowledge.
//
// A bit is four phases of DIV clocks, so a 100 MHz management clock reaches
// 400 kHz at DIV 63. The default is short so the PoC bench finishes quickly.
module fc_i2c_master #(
  parameter int DIV = 4,
  parameter logic [6:0] DEV = 7'h50
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       cmd_valid,
  output logic       cmd_ready,
  input  logic       cmd_write,
  input  logic [7:0] cmd_addr,
  input  logic [7:0] cmd_wdata,
  input  logic [5:0] cmd_rlen,
  output logic       cmd_done,
  output logic       cmd_nack,
  output logic [7:0] rx_data,
  output logic       rx_valid,
  output logic [4:0] rx_index,
  output logic       scl_oe,
  output logic       sda_oe,
  input  logic       scl_i,
  input  logic       sda_i
);
  localparam int PHW = (DIV < 1) ? 1 : DIV;
  localparam int STRETCH_MAX = 4000;

  localparam [2:0] ST_IDLE = 3'd0;
  localparam [2:0] ST_START = 3'd1;
  localparam [2:0] ST_BITS = 3'd2;
  localparam [2:0] ST_ACK = 3'd3;
  localparam [2:0] ST_RESTART = 3'd4;
  localparam [2:0] ST_STOP = 3'd5;

  localparam [2:0] K_DEVW = 3'd0;
  localparam [2:0] K_ADDR = 3'd1;
  localparam [2:0] K_DATAW = 3'd2;
  localparam [2:0] K_DEVR = 3'd3;
  localparam [2:0] K_DATAR = 3'd4;

  logic [2:0]  state;
  logic [2:0]  kind;
  logic [1:0]  phase;
  logic [15:0] wcnt;
  logic [2:0]  bitn;
  logic [7:0]  sh;
  logic [5:0]  left;
  logic [5:0]  rlen_r;
  logic [4:0]  rx_i;
  logic [15:0] stretch;
  logic        wr_r;
  logic [7:0]  addr_r;
  logic [7:0]  data_r;
  logic        nack_r;

  wire hold = ((state == ST_BITS) || (state == ST_ACK)) &&
              (phase == 2'd2) && !scl_oe && !scl_i;

  assign cmd_ready = (state == ST_IDLE);

  task automatic go_bits(input [7:0] first, input [2:0] k);
    begin
      state <= ST_BITS;
      kind  <= k;
      phase <= 2'd0;
      bitn  <= 3'd7;
      sh    <= first;
      wcnt  <= PHW[15:0] - 16'd1;
      scl_oe <= 1'b1;
      sda_oe <= (k == K_DATAR) ? 1'b0 : ~first[7];
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= ST_IDLE;
      kind    <= K_DEVW;
      phase   <= 2'd0;
      wcnt    <= 16'd0;
      bitn    <= 3'd0;
      sh      <= 8'h00;
      left    <= 6'd0;
      rlen_r  <= 6'd1;
      rx_i    <= 5'd0;
      rx_index <= 5'd0;
      stretch <= 16'd0;
      wr_r    <= 1'b0;
      addr_r  <= 8'h00;
      data_r  <= 8'h00;
      nack_r  <= 1'b0;
      cmd_done <= 1'b0;
      cmd_nack <= 1'b0;
      rx_data  <= 8'h00;
      rx_valid <= 1'b0;
      scl_oe   <= 1'b0;
      sda_oe   <= 1'b0;
    end else begin
      cmd_done <= 1'b0;
      rx_valid <= 1'b0;
      if (hold) begin
        if (stretch == STRETCH_MAX[15:0]) begin
          nack_r  <= 1'b1;
          stretch <= 16'd0;
          state   <= ST_STOP;
          phase   <= 2'd0;
          wcnt    <= PHW[15:0] - 16'd1;
          scl_oe  <= 1'b1;
          sda_oe  <= 1'b1;
        end else begin
          stretch <= stretch + 16'd1;
        end
      end else if (wcnt != 16'd0) begin
        wcnt <= wcnt - 16'd1;
        stretch <= 16'd0;
      end else begin
        stretch <= 16'd0;
        case (state)
          ST_IDLE: begin
            scl_oe <= 1'b0;
            sda_oe <= 1'b0;
            if (cmd_valid) begin
              wr_r   <= cmd_write;
              addr_r <= cmd_addr;
              data_r <= cmd_wdata;
              rlen_r <= (cmd_rlen == 6'd0) ? 6'd1 : cmd_rlen;
              nack_r <= 1'b0;
              rx_i   <= 5'd0;
              state  <= ST_START;
              phase  <= 2'd0;
              wcnt   <= PHW[15:0] - 16'd1;
              sda_oe <= 1'b1;
              scl_oe <= 1'b0;
            end
          end
          ST_START: begin
            if (phase == 2'd0) begin
              phase  <= 2'd1;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b1;
              sda_oe <= 1'b1;
            end else begin
              go_bits({DEV, 1'b0}, K_DEVW);
            end
          end
          ST_BITS: begin
            // Phases 0 and 1 keep SCL low so SDA can change. Phase 2 lets
            // SCL rise and is where a stretched clock holds the master.
            if (phase == 2'd0) begin
              phase  <= 2'd1;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b1;
            end else if (phase == 2'd1) begin
              phase  <= 2'd2;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b0;
            end else if (phase == 2'd2) begin
              phase  <= 2'd3;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b0;
            end else begin
              scl_oe <= 1'b1;
              if (kind == K_DATAR) begin
                sh <= {sh[6:0], sda_i};
                if (bitn == 3'd0) begin
                  rx_data  <= {sh[6:0], sda_i};
                  rx_valid <= 1'b1;
                  rx_index <= rx_i;
                  rx_i     <= rx_i + 5'd1;
                  state    <= ST_ACK;
                  phase    <= 2'd0;
                  wcnt     <= PHW[15:0] - 16'd1;
                  // ACK every byte except the last, which is a NACK.
                  sda_oe   <= (left > 6'd1);
                end else begin
                  bitn  <= bitn - 3'd1;
                  phase <= 2'd0;
                  wcnt  <= PHW[15:0] - 16'd1;
                  sda_oe <= 1'b0;
                end
              end else if (bitn == 3'd0) begin
                state <= ST_ACK;
                phase <= 2'd0;
                wcnt  <= PHW[15:0] - 16'd1;
                sda_oe <= 1'b0;
              end else begin
                bitn  <= bitn - 3'd1;
                sh    <= {sh[6:0], 1'b0};
                phase <= 2'd0;
                wcnt  <= PHW[15:0] - 16'd1;
                sda_oe <= ~sh[6];
              end
            end
          end
          ST_ACK: begin
            if (phase < 2'd3) begin
              phase <= phase + 2'd1;
              wcnt  <= PHW[15:0] - 16'd1;
              if (phase == 2'd1)
                scl_oe <= 1'b0;
              else if (phase == 2'd2)
                scl_oe <= 1'b0;
              else
                scl_oe <= 1'b1;
            end else begin
              scl_oe <= 1'b1;
              if ((kind != K_DATAR) && sda_i) begin
                nack_r <= 1'b1;
                state  <= ST_STOP;
                phase  <= 2'd0;
                wcnt   <= PHW[15:0] - 16'd1;
                sda_oe <= 1'b1;
              end else if (kind == K_DEVW) begin
                go_bits(addr_r, K_ADDR);
              end else if (kind == K_ADDR) begin
                if (wr_r)
                  go_bits(data_r, K_DATAW);
                else begin
                  state  <= ST_RESTART;
                  phase  <= 2'd0;
                  wcnt   <= PHW[15:0] - 16'd1;
                  scl_oe <= 1'b1;
                  sda_oe <= 1'b0;
                end
              end else if (kind == K_DATAW) begin
                state  <= ST_STOP;
                phase  <= 2'd0;
                wcnt   <= PHW[15:0] - 16'd1;
                sda_oe <= 1'b1;
              end else if (kind == K_DEVR) begin
                left <= rlen_r;
                go_bits(8'h00, K_DATAR);
              end else if (left <= 6'd1) begin
                state  <= ST_STOP;
                phase  <= 2'd0;
                wcnt   <= PHW[15:0] - 16'd1;
                sda_oe <= 1'b1;
              end else begin
                left <= left - 6'd1;
                go_bits(8'h00, K_DATAR);
              end
            end
          end
          ST_RESTART: begin
            phase <= phase + 2'd1;
            wcnt  <= PHW[15:0] - 16'd1;
            if (phase == 2'd0) begin
              scl_oe <= 1'b0;
              sda_oe <= 1'b0;
            end else if (phase == 2'd1) begin
              scl_oe <= 1'b0;
              sda_oe <= 1'b1;
            end else if (phase == 2'd2) begin
              scl_oe <= 1'b1;
              sda_oe <= 1'b1;
            end else begin
              go_bits({DEV, 1'b1}, K_DEVR);
            end
          end
          ST_STOP: begin
            if (phase == 2'd0) begin
              phase  <= 2'd1;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b0;
              sda_oe <= 1'b1;
            end else if (phase == 2'd1) begin
              phase  <= 2'd2;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b0;
              sda_oe <= 1'b0;
            end else if (phase == 2'd2) begin
              phase  <= 2'd3;
              wcnt   <= PHW[15:0] - 16'd1;
              scl_oe <= 1'b0;
              sda_oe <= 1'b0;
            end else begin
              cmd_done <= 1'b1;
              cmd_nack <= nack_r;
              state    <= ST_IDLE;
              scl_oe   <= 1'b0;
              sda_oe   <= 1'b0;
            end
          end
          default: state <= ST_IDLE;
        endcase
      end
    end
  end
endmodule
