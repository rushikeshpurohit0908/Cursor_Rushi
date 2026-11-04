// 64-bit parallel self-synchronizing scrambler, polynomial x^58 + x^39 + 1.
// Bit 0 of each block is the first bit into the LFSR. The 2-bit sync header
// is not scrambled. Reset seed is all-ones, matching the usual 64b/66b practice.
// The step is a function so bit selects stay precise in simulators that widen
// selects inside always_comb.
module fc_scrambler (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        descramble,
  input  logic        step,
  input  logic [63:0] din,
  output logic [63:0] dout
);
  logic [57:0] state;

  function automatic [121:0] scramble_word(
    input [57:0] state_in,
    input [63:0] data_in,
    input        do_descramble
  );
    integer i;
    reg [57:0] s;
    reg [63:0] y;
    reg bit_out;
    begin
      s = state_in;
      y = 64'h0;
      for (i = 0; i < 64; i = i + 1) begin
        bit_out = data_in[i] ^ s[57] ^ s[38];
        y[i] = bit_out;
        if (do_descramble)
          s = {s[56:0], data_in[i]};
        else
          s = {s[56:0], bit_out};
      end
      scramble_word = {s, y};
    end
  endfunction

  logic [121:0] stepped;
  always @(*) begin
    if (en)
      stepped = scramble_word(state, din, descramble);
    else
      stepped = {state, din};
  end
  wire [57:0] state_next = stepped[121:64];
  assign dout = stepped[63:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= {58{1'b1}};
    else if (step && en)
      state <= state_next;
  end
endmodule
