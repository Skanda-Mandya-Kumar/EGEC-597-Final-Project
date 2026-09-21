module random_replacement (
    input  wire       clk,
    input  wire       resetn,
    input  wire       advance,
    output wire [1:0] random_way
);

reg [7:0] lfsr;

wire feedback;

assign feedback =
    lfsr[7] ^
    lfsr[5] ^
    lfsr[4] ^
    lfsr[3];

always @(posedge clk) begin

    if (!resetn)
        lfsr <= 8'b10101101;

    else if (advance)
        lfsr <= {lfsr[6:0], feedback};

end

assign random_way = lfsr[1:0];

endmodule
