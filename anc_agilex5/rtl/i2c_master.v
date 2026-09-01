// i2c_master.v
// Minimal I2C write-only master (100 kHz) for audio-codec register programming.
// Open-drain SCL/SDA. Single-byte register writes: START, addr+W, reg, data, STOP.

`timescale 1ns / 1ps

module i2c_master #(
    parameter SYS_CLK_HZ = 100_000_000,
    parameter I2C_HZ     = 100_000
) (
    input  wire clk,
    input  wire reset_n,

    input  wire       start,
    input  wire [6:0] slave_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] wr_data,

    output reg        busy,
    output reg        done,
    output reg        ack_error,

    inout  wire       scl,
    inout  wire       sda
);

    localparam DIV = SYS_CLK_HZ / (I2C_HZ * 4);

    localparam S_IDLE  = 4'd0;
    localparam S_START = 4'd1;
    localparam S_BIT   = 4'd2;
    localparam S_ACK   = 4'd3;
    localparam S_STOP  = 4'd4;
    localparam S_DONE  = 4'd5;

    reg [15:0] div_cnt;
    reg        tick;
    reg [1:0]  qphase;   // 0=SCL low setup, 1=SCL rise, 2=SCL high, 3=SCL fall

    reg [3:0]  state;
    reg [2:0]  bit_idx;
    reg [1:0]  byte_idx; // 0=addr, 1=reg, 2=data
    reg [7:0]  shifter;
    reg        scl_oe;   // 1 = drive low
    reg        sda_oe;

    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_cnt <= 0;
            tick    <= 0;
            qphase  <= 0;
        end else begin
            tick <= 0;
            if (div_cnt >= DIV - 1) begin
                div_cnt <= 0;
                tick    <= 1;
                qphase  <= qphase + 1;
            end else
                div_cnt <= div_cnt + 1;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= S_IDLE;
            busy      <= 0;
            done      <= 0;
            ack_error <= 0;
            scl_oe    <= 0;
            sda_oe    <= 0;
            bit_idx   <= 7;
            byte_idx  <= 0;
            shifter   <= 0;
        end else begin
            done <= 0;

            if (state == S_IDLE) begin
                if (start) begin
                    busy      <= 1;
                    ack_error <= 0;
                    byte_idx  <= 0;
                    shifter   <= {slave_addr, 1'b0};
                    bit_idx   <= 7;
                    state     <= S_START;
                    sda_oe    <= 0;
                    scl_oe    <= 0;
                end
            end else if (tick) begin
                case (state)
                    S_START: begin
                        // START: SDA falls while SCL high
                        if (qphase == 2'd2) begin
                            sda_oe <= 1;
                            state  <= S_BIT;
                        end
                    end

                    S_BIT: begin
                        case (qphase)
                            2'd0: begin
                                scl_oe <= 1; // SCL low
                                sda_oe <= ~shifter[7];
                            end
                            2'd1: scl_oe <= 0; // SCL rise
                            2'd2: ;            // hold
                            2'd3: begin
                                scl_oe <= 1;
                                shifter <= {shifter[6:0], 1'b0};
                                if (bit_idx == 0)
                                    state <= S_ACK;
                                else
                                    bit_idx <= bit_idx - 1;
                            end
                        endcase
                    end

                    S_ACK: begin
                        case (qphase)
                            2'd0: begin
                                scl_oe <= 1;
                                sda_oe <= 0; // release SDA for ACK
                            end
                            2'd1: scl_oe <= 0;
                            2'd2: if (sda) ack_error <= 1;
                            2'd3: begin
                                scl_oe <= 1;
                                if (byte_idx == 0) begin
                                    shifter  <= reg_addr;
                                    byte_idx <= 1;
                                    bit_idx  <= 7;
                                    state    <= S_BIT;
                                end else if (byte_idx == 1) begin
                                    shifter  <= wr_data;
                                    byte_idx <= 2;
                                    bit_idx  <= 7;
                                    state    <= S_BIT;
                                end else
                                    state <= S_STOP;
                            end
                        endcase
                    end

                    S_STOP: begin
                        case (qphase)
                            2'd0: begin
                                scl_oe <= 1;
                                sda_oe <= 1;
                            end
                            2'd1: scl_oe <= 0;
                            2'd2: sda_oe <= 0; // STOP: SDA rise while SCL high
                            2'd3: state <= S_DONE;
                        endcase
                    end

                    S_DONE: begin
                        busy  <= 0;
                        done  <= 1;
                        state <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
