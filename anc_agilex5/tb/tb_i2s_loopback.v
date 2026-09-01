// tb_i2s_loopback.v
// Verifies I2S TX/RX serialization with synthetic BCLK/LRCK.

`timescale 1ns / 1ps

module tb_i2s_loopback;

    localparam DATA_WIDTH = 24;
    localparam TDM_SLOTS  = 2;

    reg bclk;
    reg lrck;
    reg reset_n;

    wire sdout;
    wire sdin;

    assign sdin = sdout;  // loopback

    reg sample_valid;
    reg signed [DATA_WIDTH-1:0] tx_slot [0:TDM_SLOTS-1];
    wire sample_rx_valid;
    wire signed [DATA_WIDTH-1:0] rx_slot [0:TDM_SLOTS-1];

    initial begin
        bclk = 0;
        forever #813 bclk = ~bclk;  // ~3.072 MHz
    end

    initial begin
        lrck = 0;
        forever #52083 lrck = ~lrck;  // ~48 kHz
    end

    i2s_tx #(.DATA_WIDTH(DATA_WIDTH), .TDM_SLOTS(TDM_SLOTS)) u_tx (
        .bclk(bclk), .lrck(lrck), .reset_n(reset_n),
        .sample_valid(sample_valid), .slot_data(tx_slot), .sdout(sdout)
    );

    i2s_rx #(.DATA_WIDTH(DATA_WIDTH), .TDM_SLOTS(TDM_SLOTS)) u_rx (
        .bclk(bclk), .lrck(lrck), .sdin(sdin), .reset_n(reset_n),
        .sample_valid(sample_rx_valid), .slot_data(rx_slot)
    );

    integer errors;
    integer frame;

    initial begin
        $dumpfile("tb_i2s_loopback.vcd");
        $dumpvars(0, tb_i2s_loopback);

        reset_n = 0;
        sample_valid = 0;
        tx_slot[0] = 24'sh123456;
        tx_slot[1] = -24'sd98765;
        errors = 0;

        repeat (10) @(posedge lrck);
        reset_n = 1;

        for (frame = 0; frame < 4; frame = frame + 1) begin
            tx_slot[0] = $random;
            tx_slot[1] = $random;
            @(posedge lrck);
            sample_valid = 1;
            @(posedge bclk);
            sample_valid = 0;

            repeat (DATA_WIDTH * TDM_SLOTS + 4) @(posedge bclk);

            @(posedge bclk);
            if (sample_rx_valid) begin
                if (rx_slot[0] !== tx_slot[0] || rx_slot[1] !== tx_slot[1]) begin
                    $display("MISMATCH frame %0d: tx=(%h,%h) rx=(%h,%h)",
                             frame, tx_slot[0], tx_slot[1], rx_slot[0], rx_slot[1]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0)
            $display("I2S loopback PASSED");
        else
            $display("I2S loopback FAILED with %0d errors", errors);

        $finish;
    end

endmodule
