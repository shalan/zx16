// zx16_alu.v -- ZX16 16-bit ALU (combinational). Verilog-2001.
// op codes are shared with the core (see localparams below; keep in sync).
module zx16_alu(
    input      [3:0]  op,
    input      [15:0] a,
    input      [15:0] b,
    input      [3:0]  shamt,   // shift amount 0..15
    output reg [15:0] y
);
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLT=4'd2, ALU_SLTU=4'd3,
               ALU_SLL=4'd4, ALU_SRL=4'd5, ALU_SRA=4'd6, ALU_OR=4'd7,
               ALU_AND=4'd8, ALU_XOR=4'd9, ALU_PASSB=4'd10;
    always @(*) begin
        case (op)
            ALU_ADD : y = a + b;
            ALU_SUB : y = a - b;
            ALU_SLT : y = ($signed(a) <  $signed(b)) ? 16'd1 : 16'd0;
            ALU_SLTU: y = (a < b)                      ? 16'd1 : 16'd0;
            ALU_SLL : y = a << shamt;
            ALU_SRL : y = a >> shamt;
            ALU_SRA : y = $signed(a) >>> shamt;
            ALU_OR  : y = a | b;
            ALU_AND : y = a & b;
            ALU_XOR : y = a ^ b;
            ALU_PASSB: y = b;
            default : y = 16'd0;
        endcase
    end
endmodule
