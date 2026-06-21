// zx16_core.v -- ZX16 single-cycle CPU core (Verilog-2001).
// One instruction per clock. Combinational fetch/decode/execute; PC, register
// file, and memory writes commit on the rising edge.
//
// ZX16 specifics encoded here (several were spec bugs fixed earlier this project):
//   * Two-operand ALU: rd/rs1 share field [8:6]. rs2 = [11:9].
//   * x0 is a NORMAL register (not hardwired zero).
//   * ORI zero-extends its imm7; all other I-type immediates sign-extend.
//   * Branches and J/JAL are PC+2-relative; AUIPC adds to the instruction's PC;
//     JR/JALR are absolute (register). JR target = reg[8:6]; JALR target = reg[11:9],
//     link -> reg[8:6].
//   * J/JAL offset = sext({imm[9:4],imm[3:1],0})  (range -512..+510).
//   * LUI/AUIPC immediate = imm9 << 7.
//   * Reset: PC = RESET_PC (0x0020, the toolchain entry convention), SP(x2)=0xF000.
//   * SYS sub-ops (func3 = inst[5:3]); see docs/INTERRUPTS.md:
//       0 ECALL (svc 0x3FF halts; svc/a0 exposed), 1 EBREAK, 2 RETI, 3 EI, 4 DI,
//       5 MFEPC rd, 6 MTEPC rd.  Trap: EPC<-PC, IE<-0, PC<-vector (J-table, entry i*2).
//       EBREAK -> vector 1 (0x0002); a hardware irq_req (when IE) -> vector irq_num.
module zx16_core #(
    parameter RESET_PC = 16'h0020
)(
    input             clk,
    input             rst,
    // hardware interrupt request (level); taken at an instruction boundary while IE=1
    input             irq_req,
    input      [3:0]  irq_num,    // vector number (vector address = irq_num*2)
    // instruction memory (async read)
    output     [15:0] iaddr,
    input      [15:0] idata,
    // data memory
    output     [15:0] daddr,
    input      [15:0] drdata,   // word read
    input      [7:0]  drbyte,   // byte read
    output            dwe,       // data write enable
    output            dword,     // 1 = word store, 0 = byte store
    output     [15:0] dwdata,
    output            dre,       // data read enable (load)
    // ecall / debug
    output            ecall_valid,
    output     [9:0]  ecall_svc,
    output     [15:0] dbg_a0,
    output            halted
);
    // ---- ALU op encoding (must match zx16_alu.v) ----
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLT=4'd2, ALU_SLTU=4'd3,
               ALU_SLL=4'd4, ALU_SRL=4'd5, ALU_SRA=4'd6, ALU_OR=4'd7,
               ALU_AND=4'd8, ALU_XOR=4'd9, ALU_PASSB=4'd10;
    // ---- opcodes ----
    localparam OP_R=3'b000, OP_I=3'b001, OP_B=3'b010, OP_S=3'b011,
               OP_L=3'b100, OP_J=3'b101, OP_U=3'b110, OP_SYS=3'b111;

    reg [15:0] pc;
    reg [15:0] epc;       // saved PC for RETI (return from interrupt/trap)
    reg        ie;        // global interrupt enable
    reg        halt_r;
    reg [15:0] regs [0:7];

    wire [15:0] inst   = idata;
    wire [2:0]  opcode = inst[2:0];
    wire [2:0]  func3  = inst[5:3];
    wire [2:0]  a_field= inst[8:6];   // rd / rs1
    wire [2:0]  b_field= inst[11:9];  // rs2
    wire [3:0]  funct4 = inst[15:12];
    wire [6:0]  imm7   = inst[15:9];
    wire [9:0]  svc    = inst[15:6];

    assign iaddr  = pc;
    assign dbg_a0 = regs[6];
    assign halted = halt_r;

    // ---- register reads ----
    wire [15:0] ra = regs[a_field];   // src1 / S-base / JR-target
    wire [15:0] rb = regs[b_field];   // src2 / L-base / JALR-target / S-data

    // ---- immediates ----
    wire [15:0] imm_i_s = {{9{imm7[6]}}, imm7};                 // sign-extended imm7
    wire [15:0] imm_i_z = {9'b0, imm7};                         // zero-extended (ORI)
    wire [15:0] imm_i   = (opcode==OP_I && func3==3'd4) ? imm_i_z : imm_i_s;
    wire [15:0] imm_ls  = {{12{inst[15]}}, inst[15:12]};        // 4-bit signed (L/S)
    wire [15:0] off_b   = {{11{inst[15]}}, inst[15:12], 1'b0};  // 5-bit signed branch
    wire [15:0] off_j   = {{6{inst[14]}}, inst[14:9], inst[5:3], 1'b0}; // 10-bit signed jump
    wire [15:0] uimm    = {inst[14:9], inst[5:3], 7'b0};        // imm9 << 7

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
        end else begin // I-type (and don't-cares for other formats)
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
    wire [3:0]  shamt = (opcode==OP_I) ? inst[12:9] : rb[3:0]; // I: imm[3:0]; R: rs2[3:0]
    wire [15:0] alu_y;
    zx16_alu u_alu(.op(alu_op), .a(alu_a), .b(alu_b), .shamt(shamt), .y(alu_y));

    // ---- instruction class helpers ----
    wire is_load  = (opcode==OP_L);
    wire is_store = (opcode==OP_S);
    wire is_jr    = (opcode==OP_R) && (funct4==4'hB);
    wire is_jalr  = (opcode==OP_R) && (funct4==4'hC);
    wire is_jal   = (opcode==OP_J) && inst[15];        // link=1
    wire is_lui   = (opcode==OP_U) && (inst[15]==1'b0);
    wire is_auipc = (opcode==OP_U) && (inst[15]==1'b1);
    wire [15:0] pc_plus2 = pc + 16'd2;

    // ---- SYS sub-functions (func3) + trap control ----
    wire is_sys    = (opcode==OP_SYS);
    wire is_ecall  = is_sys && (func3==3'd0);
    wire is_ebreak = is_sys && (func3==3'd1);
    wire is_reti   = is_sys && (func3==3'd2);
    wire is_ei     = is_sys && (func3==3'd3);
    wire is_di     = is_sys && (func3==3'd4);
    wire is_mfepc  = is_sys && (func3==3'd5);
    wire is_mtepc  = is_sys && (func3==3'd6);
    wire take_irq  = ie && irq_req && ~halt_r;        // HW interrupt at instr boundary
    wire [15:0] vec_irq = {11'b0, irq_num, 1'b0};     // irq_num * 2

    // ---- data memory interface (suppressed when servicing an interrupt) ----
    assign daddr  = is_store ? (ra + imm_ls) : (rb + imm_ls); // S base=rs1, L base=rs2
    assign dwdata = rb;                                        // S data = rs2
    assign dword  = (func3==3'd1);                            // SW
    assign dwe    = is_store && ~halt_r && ~rst && ~take_irq;
    assign dre    = is_load  && ~halt_r && ~take_irq;

    // load result (LW word / LB signed byte / LBU zero byte)
    wire [15:0] load_data = (func3==3'd1) ? drdata :
                            (func3==3'd0) ? {{8{drbyte[7]}}, drbyte} : // LB
                                            {8'b0, drbyte};            // LBU

    // ---- writeback mux ----
    wire [15:0] wb_data =
        is_mfepc           ? epc              :  // MFEPC rd <- EPC
        is_load            ? load_data        :
        (is_jal||is_jalr)  ? pc_plus2         :  // link = PC+2
        is_lui             ? uimm             :
        is_auipc           ? (pc + uimm)      :
                             alu_y;

    wire wr_en =
        (opcode==OP_I) ? 1'b1 :
        (opcode==OP_L) ? 1'b1 :
        (opcode==OP_U) ? 1'b1 :
        (opcode==OP_J) ? inst[15] :          // JAL writes, J does not
        (opcode==OP_R) ? (funct4 != 4'hB) :  // all R write except JR
        is_mfepc       ? 1'b1 :              // MFEPC writes rd
                         1'b0;               // B / S / other SYS
    wire [2:0] wr_addr = a_field;            // every writing op targets [8:6]

    // ---- branch condition ----
    wire sgn_lt = ($signed(ra) < $signed(rb));
    wire usn_lt = (ra < rb);
    reg  branch_taken;
    always @(*) begin
        case (func3)
            3'd0: branch_taken = (ra==rb);     // BEQ
            3'd1: branch_taken = (ra!=rb);     // BNE
            3'd2: branch_taken = (ra==16'd0);  // BZ  (rs1)
            3'd3: branch_taken = (ra!=16'd0);  // BNZ
            3'd4: branch_taken = sgn_lt;       // BLT
            3'd5: branch_taken = ~sgn_lt;      // BGE
            3'd6: branch_taken = usn_lt;       // BLTU
            3'd7: branch_taken = ~usn_lt;      // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // ---- next PC (interrupt/trap redirects take priority) ----
    wire [15:0] next_pc =
        take_irq                       ? vec_irq :        // HW interrupt -> vector
        is_ebreak                      ? 16'h0002 :       // EBREAK -> vector 1
        is_reti                        ? epc :            // RETI -> EPC
        (opcode==OP_B && branch_taken) ? (pc_plus2 + off_b) :
        (opcode==OP_J)                 ? (pc_plus2 + off_j) :
        is_jr                          ? ra :   // JR  : PC <- reg[8:6]
        is_jalr                        ? rb :   // JALR: PC <- reg[11:9]
                                         pc_plus2;

    // ---- ecall (only real ECALL, not the new SYS sub-ops, and not during a trap) ----
    assign ecall_valid = is_ecall && ~halt_r && ~take_irq;
    assign ecall_svc   = svc;

    // ---- sequential state ----
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            pc     <= RESET_PC;
            epc    <= 16'd0;
            ie     <= 1'b0;
            halt_r <= 1'b0;
            for (i=0;i<8;i=i+1) regs[i] <= 16'd0;
            regs[2] <= 16'hF000;          // SP
        end else if (!halt_r) begin
            pc <= next_pc;
            if (take_irq) begin
                epc <= pc;                // save the interrupted PC; instruction is re-run
                ie  <= 1'b0;              // mask further interrupts
            end else begin
                if (wr_en) regs[wr_addr] <= wb_data;
                if      (is_ebreak) begin epc <= pc; ie <= 1'b0; end
                else if (is_reti)   ie  <= 1'b1;
                else if (is_ei)     ie  <= 1'b1;
                else if (is_di)     ie  <= 1'b0;
                else if (is_mtepc)  epc <= regs[a_field];
                if (is_ecall && svc==10'h3FF) halt_r <= 1'b1;
            end
        end
    end
endmodule
