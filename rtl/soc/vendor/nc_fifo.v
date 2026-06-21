`timescale 1ns/1ps

/*
    A FIFO
    Depth = 2^AW
    Width = DW
*/
module nc_fifo #(parameter DW=8, AW=4)(
    input   wire            clk,
    input   wire            rst_n,
    input   wire            rd,
    input   wire            wr,
    input   wire            flush,
    input   wire [DW-1:0]   wdata,
    output  wire            empty,
    output  wire            full,
    output  wire [DW-1:0]   rdata,
    output  wire [AW:0]     level    // AW+1 bits to represent 0 to 2^AW entries
);

    localparam  DEPTH = 2**AW;

    //Internal Signal declarations
    reg [DW-1:0]  array_reg [DEPTH-1:0];
    reg [AW-1:0]  w_ptr_reg;
    reg [AW-1:0]  w_ptr_next;
    reg [AW-1:0]  w_ptr_succ;
    reg [AW-1:0]  r_ptr_reg;
    reg [AW-1:0]  r_ptr_next;
    reg [AW-1:0]  r_ptr_succ;

    // Level
    reg [AW:0] level_reg;    // AW+1 bits to represent 0 to 2^AW entries
    reg [AW:0] level_next;      
    reg full_reg;
    reg empty_reg;
    reg full_next;
    reg empty_next;

    wire w_en;

    always @ (posedge clk)
        if(w_en) begin
            array_reg[w_ptr_reg] <= wdata;
        end

    assign rdata = array_reg[r_ptr_reg];   
    assign w_en = wr & ~full_reg;           

    //State Machine
    always @ (posedge clk, negedge rst_n) begin
        if(!rst_n)
            begin
                w_ptr_reg <= 'b0;
                r_ptr_reg <= 'b0;
                full_reg  <= 1'b0;
                empty_reg <= 1'b1;
                level_reg <= 'd0;
            end
        else if(flush)
            begin
                w_ptr_reg <= 'b0;
                r_ptr_reg <= 'b0;
                full_reg  <= 1'b0;
                empty_reg <= 1'b1;
                level_reg <= 'd0;
            end
        else
            begin
                w_ptr_reg <= w_ptr_next;
                r_ptr_reg <= r_ptr_next;
                full_reg  <= full_next;
                empty_reg <= empty_next;
                level_reg <= level_next;
            end
    end

    //Next State Logic
    always @* begin
        w_ptr_succ  =   w_ptr_reg + 1;
        r_ptr_succ  =   r_ptr_reg + 1;
        w_ptr_next  =   w_ptr_reg;
        r_ptr_next  =   r_ptr_reg;
        full_next   =   full_reg;
        empty_next  =   empty_reg;
        level_next  =   level_reg;

        case({w_en,rd})
            //2'b00: nop
            2'b01: 
                if(~empty_reg) begin
                    r_ptr_next = r_ptr_succ;
                    full_next = 1'b0;
                    level_next = level_reg - 1;
                    if (r_ptr_succ == w_ptr_reg)
                        empty_next = 1'b1;
                end
            
            2'b10: 
                if(~full_reg) begin
                    w_ptr_next = w_ptr_succ;
                    empty_next = 1'b0;
                    level_next = level_reg + 1;
                    if (w_ptr_succ == r_ptr_reg)
                        full_next = 1'b1;
                end
            
            2'b11: begin
                w_ptr_next = w_ptr_succ;
                r_ptr_next = r_ptr_succ;
            end
        endcase
    end

    //Set Full and Empty
    assign full = full_reg;
    assign empty = empty_reg;
    assign level = level_reg;
  
endmodule
