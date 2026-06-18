// zx16_core_ahb.v -- ZX16 CPU, 2-stage pipeline, dual AHB-Lite masters (Verilog-2001).
//
// The memory is fully decoupled: the core is an AHB-Lite master on two independent
// buses (instruction + data); memory and peripherals are external AHB-Lite slaves.
//
// Pipeline maps onto AHB's two phases:
//   FETCH  = I-bus address phase (drive HADDR = PC)
//   EXECUTE= I-bus data phase    (instruction on HRDATA -> decode/ALU/branch/regwrite)
// so the fetch of instruction i+1 overlaps the execute of i (~1 CPI on straight code).
//
// Hazard policy (kept deliberately simple, no forwarding):
//   * taken branch/jump  -> 1-cycle flush (squash the in-flight fetch)
//   * load/store         -> serialized: I-bus idles, D-bus does addr then data phase,
//                           then the pipeline refills (memory ops cost a few cycles)
//   * HREADY low         -> freeze: hold bus address/control and all pipeline state
//
// Reuses zx16_alu.v. ECALL: svc 0x3FF halts; svc/a0 exposed for the environment.
module zx16_core_ahb #(
    parameter RESET_PC = 16'h0020
)(
    input             HCLK,
    input             HRESETn,        // async, active-low (AHB convention)
    // ---- Instruction AHB-Lite master ----
    output     [15:0] I_HADDR,
    output     [1:0]  I_HTRANS,
    output            I_HWRITE,
    output     [2:0]  I_HSIZE,
    output     [2:0]  I_HBURST,
    output     [3:0]  I_HPROT,
    output     [15:0] I_HWDATA,
    input      [15:0] I_HRDATA,
    input             I_HREADY,
    input             I_HRESP,
    // ---- Data AHB-Lite master ----
    output     [15:0] D_HADDR,
    output     [1:0]  D_HTRANS,
    output            D_HWRITE,
    output     [2:0]  D_HSIZE,
    output     [2:0]  D_HBURST,
    output     [3:0]  D_HPROT,
    output     [15:0] D_HWDATA,
    input      [15:0] D_HRDATA,
    input             D_HREADY,
    input             D_HRESP,
    // ---- ecall / debug ----
    output            ecall_valid,
    output     [9:0]  ecall_svc,
    output     [15:0] dbg_a0,
    output            halted
);
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLT=4'd2, ALU_SLTU=4'd3,
               ALU_SLL=4'd4, ALU_SRL=4'd5, ALU_SRA=4'd6, ALU_OR=4'd7,
               ALU_AND=4'd8, ALU_XOR=4'd9, ALU_PASSB=4'd10;
    localparam OP_R=3'b000, OP_I=3'b001, OP_B=3'b010, OP_S=3'b011,
               OP_L=3'b100, OP_J=3'b101, OP_U=3'b110, OP_SYS=3'b111;
    localparam TRANS_IDLE=2'b00, TRANS_NONSEQ=2'b10;

    // ---- pipeline / bus state ----
    reg [15:0] pcF;        // address presented on the I-bus this cycle (fetch)
    reg [15:0] pcE;        // PC of the instruction in EXECUTE
    reg        validE;     // EXECUTE holds a real instruction (not a bubble)
    reg        memph;      // 1 = in the data phase of a load/store
    reg [15:0] instr_l;    // instruction latched for the load/store data-phase cycle
    reg        halt_r;
    reg [15:0] regs [0:7];
    integer i;

    // EXECUTE instruction: from the I-bus data phase, or the latch during a mem op.
    wire [15:0] inst   = memph ? instr_l : I_HRDATA;
    wire [2:0]  opcode = inst[2:0];
    wire [2:0]  func3  = inst[5:3];
    wire [2:0]  a_field= inst[8:6];
    wire [2:0]  b_field= inst[11:9];
    wire [3:0]  funct4 = inst[15:12];
    wire [6:0]  imm7   = inst[15:9];
    wire [9:0]  svc    = inst[15:6];

    wire [15:0] ra = regs[a_field];
    wire [15:0] rb = regs[b_field];
    assign dbg_a0 = regs[6];
    assign halted = halt_r;

    // ---- immediates ----
    wire [15:0] imm_i_s = {{9{imm7[6]}}, imm7};
    wire [15:0] imm_i_z = {9'b0, imm7};
    wire [15:0] imm_i   = (opcode==OP_I && func3==3'd4) ? imm_i_z : imm_i_s;
    wire [15:0] imm_ls  = {{12{inst[15]}}, inst[15:12]};
    wire [15:0] off_b   = {{11{inst[15]}}, inst[15:12], 1'b0};
    wire [15:0] off_j   = {{6{inst[14]}}, inst[14:9], inst[5:3], 1'b0};
    wire [15:0] uimm    = {inst[14:9], inst[5:3], 7'b0};

    // ---- ALU control ----
    reg [3:0] alu_op;
    always @(*) begin
        if (opcode==OP_R) begin
            case (funct4)
                4'h0: alu_op=ALU_ADD;  4'h1: alu_op=ALU_SUB;  4'h2: alu_op=ALU_SLT;
                4'h3: alu_op=ALU_SLTU; 4'h4: alu_op=ALU_SLL;  4'h5: alu_op=ALU_SRL;
                4'h6: alu_op=ALU_SRA;  4'h7: alu_op=ALU_OR;   4'h8: alu_op=ALU_AND;
                4'h9: alu_op=ALU_XOR;  4'hA: alu_op=ALU_PASSB; default: alu_op=ALU_ADD;
            endcase
        end else begin
            case (func3)
                3'd0: alu_op=ALU_ADD;  3'd1: alu_op=ALU_SLT;  3'd2: alu_op=ALU_SLTU;
                3'd4: alu_op=ALU_OR;   3'd5: alu_op=ALU_AND;  3'd6: alu_op=ALU_XOR;
                3'd7: alu_op=ALU_PASSB;
                3'd3: case (imm7[6:4])
                        3'b001: alu_op=ALU_SLL; 3'b010: alu_op=ALU_SRL;
                        3'b100: alu_op=ALU_SRA; default: alu_op=ALU_SLL;
                      endcase
                default: alu_op=ALU_ADD;
            endcase
        end
    end
    wire [15:0] alu_a = ra;
    wire [15:0] alu_b = (opcode==OP_I) ? imm_i : rb;
    wire [3:0]  shamt = (opcode==OP_I) ? inst[12:9] : rb[3:0];
    wire [15:0] alu_y;
    zx16_alu u_alu(.op(alu_op), .a(alu_a), .b(alu_b), .shamt(shamt), .y(alu_y));

    // ---- instruction classes ----
    wire is_load  = (opcode==OP_L);
    wire is_store = (opcode==OP_S);
    wire is_mem   = is_load | is_store;
    wire is_jr    = (opcode==OP_R) && (funct4==4'hB);
    wire is_jalr  = (opcode==OP_R) && (funct4==4'hC);
    wire is_jal   = (opcode==OP_J) && inst[15];
    wire is_lui   = (opcode==OP_U) && (inst[15]==1'b0);
    wire is_auipc = (opcode==OP_U) && (inst[15]==1'b1);
    wire [15:0] pc_plus2 = pcE + 16'd2;

    // ---- branch / next sequential PC (computed in EXECUTE) ----
    wire sgn_lt = ($signed(ra) < $signed(rb));
    wire usn_lt = (ra < rb);
    reg  branch_taken;
    always @(*) begin
        case (func3)
            3'd0: branch_taken=(ra==rb);    3'd1: branch_taken=(ra!=rb);
            3'd2: branch_taken=(ra==16'd0); 3'd3: branch_taken=(ra!=16'd0);
            3'd4: branch_taken=sgn_lt;      3'd5: branch_taken=~sgn_lt;
            3'd6: branch_taken=usn_lt;      3'd7: branch_taken=~usn_lt;
            default: branch_taken=1'b0;
        endcase
    end
    wire take_branch = (opcode==OP_B) && branch_taken;
    wire redirect    = take_branch || (opcode==OP_J) || is_jr || is_jalr;
    wire [15:0] target =
        take_branch ? (pc_plus2 + off_b) :
        (opcode==OP_J) ? (pc_plus2 + off_j) :
        is_jr   ? ra :
        is_jalr ? rb :
                  pc_plus2;

    // ---- data bus (load/store) ----
    wire [15:0] daddr_w = is_store ? (ra + imm_ls) : (rb + imm_ls);
    wire [7:0]  dbyte = daddr_w[0] ? D_HRDATA[15:8] : D_HRDATA[7:0];
    wire [15:0] load_data = (func3==3'd1) ? D_HRDATA :              // LW
                            (func3==3'd0) ? {{8{dbyte[7]}}, dbyte} : // LB  (sign-extend)
                                            {8'b0, dbyte};           // LBU (zero-extend)

    // ---- writeback ----
    wire [15:0] wb_data =
        is_load           ? load_data :
        (is_jal||is_jalr) ? pc_plus2  :
        is_lui            ? uimm      :
        is_auipc          ? (pcE + uimm) :
                            alu_y;
    wire wr_en =
        (opcode==OP_I) ? 1'b1 :
        (opcode==OP_L) ? 1'b1 :
        (opcode==OP_U) ? 1'b1 :
        (opcode==OP_J) ? inst[15] :
        (opcode==OP_R) ? (funct4 != 4'hB) :
                         1'b0;
    wire [2:0] wr_addr = a_field;
    wire is_ecall = (opcode==OP_SYS);

    // ---- control: when is EXECUTE active / which bus phase ----
    wire exec_avail = validE && I_HREADY;            // E instruction valid this cycle
    wire mem_start  = exec_avail && is_mem && !memph; // begin a load/store (D addr phase)

    // I-bus: fetch unless halted, in a mem data phase, or starting a mem op (idle then)
    wire do_fetch = !halt_r && !memph && !mem_start;
    assign I_HADDR  = pcF;
    assign I_HTRANS = do_fetch ? TRANS_NONSEQ : TRANS_IDLE;
    assign I_HWRITE = 1'b0;
    assign I_HSIZE  = 3'b001;
    assign I_HBURST = 3'b000;
    assign I_HPROT  = 4'b0010;
    assign I_HWDATA = 16'd0;

    // D-bus: address phase when starting a mem op; data phase while memph
    assign D_HADDR  = daddr_w;
    assign D_HTRANS = mem_start ? TRANS_NONSEQ : TRANS_IDLE;
    assign D_HWRITE = is_store;
    assign D_HSIZE  = (func3==3'd1) ? 3'b001 : 3'b000;   // SW/LW halfword, byte otherwise
    assign D_HBURST = 3'b000;
    assign D_HPROT  = 4'b0011;
    // store data positioned by byte lane for SB; driven in the data phase
    assign D_HWDATA = (func3==3'd1) ? rb :
                      daddr_w[0] ? {rb[7:0], 8'b0} : {8'b0, rb[7:0]};

    assign ecall_valid = exec_avail && is_ecall && !memph;
    assign ecall_svc   = svc;

    // ---- sequential ----
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            pcF <= RESET_PC; pcE <= 16'd0; validE <= 1'b0;
            memph <= 1'b0; halt_r <= 1'b0; instr_l <= 16'd0;
            for (i=0;i<8;i=i+1) regs[i] <= 16'd0;
            regs[2] <= 16'hF000;
        end else if (halt_r) begin
            // frozen
        end else if (memph) begin
            // ---- load/store data phase ----
            if (D_HREADY) begin
                if (wr_en) regs[wr_addr] <= wb_data;   // load writeback (store: wr_en=0)
                memph  <= 1'b0;
                pcF    <= pcE + 16'd2;   // refetch the instruction after the mem op
                validE <= 1'b0;          // refill bubble
            end
            // else: wait state -> hold
        end else if (validE) begin
            if (I_HREADY) begin
                if (is_mem) begin
                    instr_l <= inst;     // latch; D addr phase issued this cycle
                    memph   <= 1'b1;
                end else begin
                    if (wr_en) regs[wr_addr] <= wb_data;
                    if (is_ecall && svc==10'h3FF) halt_r <= 1'b1;
                    if (redirect) begin
                        pcF <= target; validE <= 1'b0;          // flush
                    end else begin
                        pcE <= pcF; pcF <= pcF + 16'd2; validE <= 1'b1;
                    end
                end
            end
            // else: fetch wait state -> hold
        end else begin
            // ---- bubble: address phase of pcF in flight; capture next cycle ----
            if (I_HREADY) begin
                pcE <= pcF; pcF <= pcF + 16'd2; validE <= 1'b1;
            end
        end
    end
endmodule
