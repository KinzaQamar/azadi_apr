

/**
 * Instruction Fetch Stage
 *
 * Instruction fetch unit: Selection of the next PC, and buffering (sampling) of
 * the read instruction.
 */



module brq_ifu #(
    parameter int unsigned DmHaltAddr        = 32'h1A110800,
    parameter int unsigned DmExceptionAddr   = 32'h1A110808,
    parameter bit          DummyInstructions = 1'b0,
    parameter bit          ICache            = 1'b0,
    parameter bit          ICacheECC         = 1'b0,
    parameter bit          PCIncrCheck       = 1'b0,
    parameter bit          BranchPredictor   = 1'b0
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic [31:0]            boot_addr_i,              // also used for mtvec
    input  logic                   req_i,                    // instruction request control

    // instruction cache interface
    output logic                  instr_req_o,
    output logic [31:0]           instr_addr_o,
    input  logic                  instr_gnt_i,
    input  logic                  instr_rvalid_i,
    input  logic [31:0]           instr_rdata_i,
    input  logic                  instr_err_i,
    input  logic                  instr_pmp_err_i,

    // output of ID stage
    output logic                  instr_valid_id_o,         // instr in IF-ID is valid
    output logic                  instr_new_id_o,           // instr in IF-ID is new
    output logic [31:0]           instr_rdata_id_o,         // instr for ID stage
    output logic [31:0]           instr_rdata_alu_id_o,     // replicated instr for ID stage
                                                            // to reduce fan-out
    output logic [15:0]           instr_rdata_c_id_o,       // compressed instr for ID stage
                                                            // (mtval), meaningful only if
                                                            // instr_is_compressed_id_o = 1'b1
    output logic                  instr_is_compressed_id_o, // compressed decoder thinks this
                                                            // is a compressed instr
    output logic                  instr_bp_taken_o,         // instruction was predicted to be
                                                            // a taken branch
    output logic                  instr_fetch_err_o,        // bus error on fetch
    output logic                  instr_fetch_err_plus2_o,  // bus error misaligned
    output logic                  illegal_c_insn_id_o,      // compressed decoder thinks this
                                                            // is an invalid instr
    output logic                  dummy_instr_id_o,         // Instruction is a dummy
    output logic [31:0]           pc_if_o,
    output logic [31:0]           pc_id_o,

    // control signals
    input  logic                  instr_valid_clear_i,      // clear instr valid bit in IF-ID
    input  logic                  pc_set_i,                 // set the PC to a new value
    input  logic                  pc_set_spec_i,
    input  brq_pkg::pc_sel_e      pc_mux_i,                 // selector for PC multiplexer
    input  logic                  nt_branch_mispredict_i,   // Not-taken branch in ID/EX was
                                                            // mispredicted (predicted taken)
    input  brq_pkg::exc_pc_sel_e exc_pc_mux_i,             // selects ISR address
    input  brq_pkg::exc_cause_e  exc_cause,                // selects ISR address for
                                                            // vectorized interrupt lines
    input logic                   dummy_instr_en_i,
    input logic [2:0]             dummy_instr_mask_i,
    input logic                   dummy_instr_seed_en_i,
    input logic [31:0]            dummy_instr_seed_i,
    input logic                   icache_enable_i,
    input logic                   icache_inval_i,

    // jump and branch target
    input  logic [31:0]           branch_target_ex_i,       // branch/jump target address

    // CSRs
    input  logic [31:0]           csr_mepc_i,               // PC to restore after handling
                                                            // the interrupt/exception
    input  logic [31:0]           csr_depc_i,               // PC to restore after handling
                                                            // the debug request
    input  logic [31:0]           csr_mtvec_i,              // base PC to jump to on exception
    output logic                  csr_mtvec_init_o,         // tell CS regfile to init mtvec

    // pipeline stall
    input  logic                  id_in_ready_i,            // ID stage is ready for new instr

    // misc signals
    output logic                  pc_mismatch_alert_o,
    output logic                  if_busy_o                 // IF stage is busy fetching instr
);

  import brq_pkg::*;

  logic              instr_valid_id_d, instr_valid_id_q;
  logic              instr_new_id_d, instr_new_id_q;

  // prefetch buffer related signals
  logic              prefetch_busy;
  logic              branch_req;
  logic              branch_spec;
  logic              predicted_branch;
  logic       [31:0] fetch_addr_n;
  logic              unused_fetch_addr_n0;

  logic              fetch_valid;
  logic              fetch_ready;
  logic       [31:0] fetch_rdata;
  logic       [31:0] fetch_addr;
  logic              fetch_err;
  logic              fetch_err_plus2;

  logic              if_instr_valid;
  logic       [31:0] if_instr_rdata;
  logic       [31:0] if_instr_addr;
  logic              if_instr_err;

  logic       [31:0] exc_pc;

  logic        [5:0] irq_id;
  logic              unused_irq_bit;

  logic              if_id_pipe_reg_we; // IF-ID pipeline reg write enable

  // Dummy instruction signals
  logic              stall_dummy_instr;
  logic [31:0]       instr_out;
  logic              instr_is_compressed_out;
  logic              illegal_c_instr_out;
  logic              instr_err_out;

  logic              predict_branch_taken;
  logic       [31:0] predict_branch_pc;

  brq_pkg::pc_sel_e pc_mux_internal;

  logic        [7:0] unused_boot_addr;
  logic        [7:0] unused_csr_mtvec;

  assign unused_boot_addr = boot_addr_i[7:0];
  assign unused_csr_mtvec = csr_mtvec_i[7:0];

  // extract interrupt ID from exception cause
  assign irq_id         = {exc_cause};
  assign unused_irq_bit = irq_id[5];   // MSB distinguishes interrupts from exceptions

  // exception PC selection mux
  always_comb begin : exc_pc_mux
    unique case (exc_pc_mux_i)
      EXC_PC_EXC:     exc_pc = { csr_mtvec_i[31:8], 8'h00                    };
      EXC_PC_IRQ:     exc_pc = { csr_mtvec_i[31:8], 1'b0, irq_id[4:0], 2'b00 };
      EXC_PC_DBD:     exc_pc = DmHaltAddr;
      EXC_PC_DBG_EXC: exc_pc = DmExceptionAddr;
      //default:        exc_pc = { csr_mtvec_i[31:8], 8'h00                    };
    endcase
  end

  // The Branch predictor can provide a new PC which is internal to ifu. Only override the mux
  // select to choose this if the core isn't already trying to set a PC.
  assign pc_mux_internal =
    (BranchPredictor && predict_branch_taken && !pc_set_i) ? PC_BP : pc_mux_i;

  // fetch address selection mux
  always_comb begin : fetch_addr_mux
    unique case (pc_mux_internal)
      PC_BOOT: fetch_addr_n = { boot_addr_i[31:8], 8'h00 };
      PC_JUMP: fetch_addr_n = branch_target_ex_i;
      PC_EXC:  fetch_addr_n = exc_pc;                       // set PC to exception handler
      PC_ERET: fetch_addr_n = csr_mepc_i;                   // restore PC when returning from EXC
      PC_DRET: fetch_addr_n = csr_depc_i;
      // Without branch predictor will never get pc_mux_internal == PC_BP. We still handle no branch
      // predictor case here to ensure redundant mux logic isn't synthesised.
      PC_BP:   fetch_addr_n = BranchPredictor ? predict_branch_pc : { boot_addr_i[31:8], 8'h00 };
      default: fetch_addr_n = { boot_addr_i[31:8], 8'h00 };
    endcase
  end

  // tell CS register file to initialize mtvec on boot
  assign csr_mtvec_init_o = (pc_mux_i == PC_BOOT) & pc_set_i;

  if (ICache) begin : gen_ifu_icache
    // Full I-Cache option
    brq_ifu_icache #(
      .BranchPredictor (BranchPredictor),
      .ICacheECC       (ICacheECC)
    ) icache_i (
        .clk_i               ( clk_i                      ),
        .rst_ni              ( rst_ni                     ),

        .req_i               ( req_i                      ),

        .branch_i            ( branch_req                 ),
        .branch_spec_i       ( branch_spec                ),
        .predicted_branch_i  ( predicted_branch           ),
        .branch_mispredict_i ( nt_branch_mispredict_i     ),
        .addr_i              ( {fetch_addr_n[31:1], 1'b0} ),

        .ready_i             ( fetch_ready                ),
        .valid_o             ( fetch_valid                ),
        .rdata_o             ( fetch_rdata                ),
        .addr_o              ( fetch_addr                 ),
        .err_o               ( fetch_err                  ),
        .err_plus2_o         ( fetch_err_plus2            ),

        .instr_req_o         ( instr_req_o                ),
        .instr_addr_o        ( instr_addr_o               ),
        .instr_gnt_i         ( instr_gnt_i                ),
        .instr_rvalid_i      ( instr_rvalid_i             ),
        .instr_rdata_i       ( instr_rdata_i              ),
        .instr_err_i         ( instr_err_i                ),
        .instr_pmp_err_i     ( instr_pmp_err_i            ),

        .icache_enable_i     ( icache_enable_i            ),
        .icache_inval_i      ( icache_inval_i             ),
        .busy_o              ( prefetch_busy              )
    );
  end else begin : gen_ifu_prefetch_buffer
    // prefetch buffer, caches a fixed number of instructions
    brq_ifu_prefetch_buffer #(
      .BranchPredictor (BranchPredictor)
    ) ifu_prefetch_buffer_i (
        .clk_i               ( clk_i                      ),
        .rst_ni              ( rst_ni                     ),

        .req_i               ( req_i                      ),

        .branch_i            ( branch_req                 ),
        .branch_spec_i       ( branch_spec                ),
        .predicted_branch_i  ( predicted_branch           ),
        .branch_mispredict_i ( nt_branch_mispredict_i     ),
        .addr_i              ( {fetch_addr_n[31:1], 1'b0} ),

        .ready_i             ( fetch_ready                ),
        .valid_o             ( fetch_valid                ),
        .rdata_o             ( fetch_rdata                ),
        .addr_o              ( fetch_addr                 ),
        .err_o               ( fetch_err                  ),
        .err_plus2_o         ( fetch_err_plus2            ),

        .instr_req_o         ( instr_req_o                ),
        .instr_addr_o        ( instr_addr_o               ),
        .instr_gnt_i         ( instr_gnt_i                ),
        .instr_rvalid_i      ( instr_rvalid_i             ),
        .instr_rdata_i       ( instr_rdata_i              ),
        .instr_err_i         ( instr_err_i                ),
        .instr_pmp_err_i     ( instr_pmp_err_i            ),

        .busy_o              ( prefetch_busy              )
    );
    // ICache tieoffs
    logic unused_icen, unused_icinv;
    assign unused_icen  = icache_enable_i;
    assign unused_icinv = icache_inval_i;
  end

  assign unused_fetch_addr_n0 = fetch_addr_n[0];

  assign branch_req  = pc_set_i | predict_branch_taken;
  assign branch_spec = pc_set_spec_i | predict_branch_taken;

  assign pc_if_o     = if_instr_addr;
  assign if_busy_o   = prefetch_busy;

  // compressed instruction decoding, or more precisely compressed instruction
  // expander
  //
  // since it does not matter where we decompress instructions, we do it here
  // to ease timing closure
  logic [31:0] instr_decompressed;
  logic        illegal_c_insn;
  logic        instr_is_compressed;

  brq_ifu_compressed_decoder ifu_compressed_decoder_i (
      .clk_i           ( clk_i                    ),
      .rst_ni          ( rst_ni                   ),
      .valid_i         ( fetch_valid & ~fetch_err ),
      .instr_i         ( if_instr_rdata           ),
      .instr_o         ( instr_decompressed       ),
      .is_compressed_o ( instr_is_compressed      ),
      .illegal_instr_o ( illegal_c_insn           )
  );

  // Dummy instruction insertion
  if (DummyInstructions) begin : gen_dummy_instr
    logic        insert_dummy_instr;
    logic [31:0] dummy_instr_data;

    brq_ifu_dummy_instr dummy_instr_i (
      .clk_i                 ( clk_i                 ),
      .rst_ni                ( rst_ni                ),
      .dummy_instr_en_i      ( dummy_instr_en_i      ),
      .dummy_instr_mask_i    ( dummy_instr_mask_i    ),
      .dummy_instr_seed_en_i ( dummy_instr_seed_en_i ),
      .dummy_instr_seed_i    ( dummy_instr_seed_i    ),
      .fetch_valid_i         ( fetch_valid           ),
      .id_in_ready_i         ( id_in_ready_i         ),
      .insert_dummy_instr_o  ( insert_dummy_instr    ),
      .dummy_instr_data_o    ( dummy_instr_data      )
    );

    // Mux between actual instructions and dummy instructions
    assign instr_out               = insert_dummy_instr ? dummy_instr_data : instr_decompressed;
    assign instr_is_compressed_out = insert_dummy_instr ? 1'b0 : instr_is_compressed;
    assign illegal_c_instr_out     = insert_dummy_instr ? 1'b0 : illegal_c_insn;
    assign instr_err_out           = insert_dummy_instr ? 1'b0 : if_instr_err;

    // Stall the IF stage if we insert a dummy instruction. The dummy will execute between whatever
    // is currently in the ID stage and whatever is valid from the prefetch buffer this cycle. The
    // PC of the dummy instruction will match whatever is next from the prefetch buffer.
    assign stall_dummy_instr = insert_dummy_instr;

    // Register the dummy instruction indication into the ID stage
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        dummy_instr_id_o <= 1'b0;
      end else if (if_id_pipe_reg_we) begin
        dummy_instr_id_o <= insert_dummy_instr;
      end
    end

  end else begin : gen_no_dummy_instr
    logic        unused_dummy_en;
    logic [2:0]  unused_dummy_mask;
    logic        unused_dummy_seed_en;
    logic [31:0] unused_dummy_seed;

    assign unused_dummy_en         = dummy_instr_en_i;
    assign unused_dummy_mask       = dummy_instr_mask_i;
    assign unused_dummy_seed_en    = dummy_instr_seed_en_i;
    assign unused_dummy_seed       = dummy_instr_seed_i;
    assign instr_out               = instr_decompressed;
    assign instr_is_compressed_out = instr_is_compressed;
    assign illegal_c_instr_out     = illegal_c_insn;
    assign instr_err_out           = if_instr_err;
    assign stall_dummy_instr       = 1'b0;
    assign dummy_instr_id_o        = 1'b0;
  end

  // The ID stage becomes valid as soon as any instruction is registered in the ID stage flops.
  // Note that the current instruction is squashed by the incoming pc_set_i signal.
  // Valid is held until it is explicitly cleared (due to an instruction completing or an exception)
  assign instr_valid_id_d = (if_instr_valid & id_in_ready_i & ~pc_set_i) |
                            (instr_valid_id_q & ~instr_valid_clear_i);
  assign instr_new_id_d   = if_instr_valid & id_in_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_valid_id_q <= 1'b0;
      instr_new_id_q   <= 1'b0;
    end else begin
      instr_valid_id_q <= instr_valid_id_d;
      instr_new_id_q   <= instr_new_id_d;
    end
  end

  assign instr_valid_id_o = instr_valid_id_q;
  // Signal when a new instruction enters the ID stage (only used for RVFI signalling).
  assign instr_new_id_o   = instr_new_id_q;

  // IF-ID pipeline registers, frozen when the ID stage is stalled
  assign if_id_pipe_reg_we = instr_new_id_d;

  always_ff @(posedge clk_i) begin
    if (if_id_pipe_reg_we) begin
      instr_rdata_id_o         <= instr_out;
      // To reduce fan-out and help timing from the instr_rdata_id flops they are replicated.
      instr_rdata_alu_id_o     <= instr_out;
      instr_fetch_err_o        <= instr_err_out;
      instr_fetch_err_plus2_o  <= fetch_err_plus2;
      instr_rdata_c_id_o       <= if_instr_rdata[15:0];
      instr_is_compressed_id_o <= instr_is_compressed_out;
      illegal_c_insn_id_o      <= illegal_c_instr_out;
      pc_id_o                  <= pc_if_o;
    end
  end

  // Check for expected increments of the PC when security hardening enabled
  if (PCIncrCheck) begin : g_secure_pc
    logic [31:0] prev_instr_addr_incr;
    logic        prev_instr_seq_q, prev_instr_seq_d;

    // Do not check for sequential increase after a branch, jump, exception, interrupt or debug
    // request, all of which will set branch_req. Also do not check after reset or for dummys.
    assign prev_instr_seq_d = (prev_instr_seq_q | instr_new_id_d) &
        ~branch_req & ~stall_dummy_instr;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        prev_instr_seq_q <= 1'b0;
      end else begin
        prev_instr_seq_q <= prev_instr_seq_d;
      end
    end

    assign prev_instr_addr_incr = pc_id_o + ((instr_is_compressed_id_o && !instr_fetch_err_o) ?
                                             32'd2 : 32'd4);

    // Check that the address equals the previous address +2/+4
    assign pc_mismatch_alert_o = prev_instr_seq_q & (pc_if_o != prev_instr_addr_incr);

  end else begin : g_no_secure_pc
    assign pc_mismatch_alert_o = 1'b0;
  end

  if (BranchPredictor) begin : g_ifu_branch_predictor
    logic [31:0] instr_skid_data_q;
    logic [31:0] instr_skid_addr_q;
    logic        instr_skid_bp_taken_q;
    logic        instr_skid_valid_q, instr_skid_valid_d;
    logic        instr_skid_en;
    logic        instr_bp_taken_q, instr_bp_taken_d;

    logic        predict_branch_taken_raw;

    // ID stages needs to know if branch was predicted taken so it can signal mispredicts
    always_ff @(posedge clk_i) begin
      if (if_id_pipe_reg_we) begin
        instr_bp_taken_q <= instr_bp_taken_d;
      end
    end

    // When branch prediction is enabled a skid buffer between the IF and ID/EX stage is introduced.
    // If an instruction in IF is predicted to be a taken branch and ID/EX is not ready the
    // instruction in IF is moved to the skid buffer which becomes the output of the IF stage until
    // the ID/EX stage accepts the instruction. The skid buffer is required as otherwise the ID/EX
    // ready signal is coupled to the instr_req_o output which produces a feedthrough path from
    // data_gnt_i -> instr_req_o (which needs to be avoided as for some interconnects this will
    // result in a combinational loop).

    assign instr_skid_en = predicted_branch & ~id_in_ready_i & ~instr_skid_valid_q;

    assign instr_skid_valid_d = (instr_skid_valid_q & ~id_in_ready_i & ~stall_dummy_instr) |
                                instr_skid_en;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        instr_skid_valid_q <= 1'b0;
      end else begin
        instr_skid_valid_q <= instr_skid_valid_d;
      end
    end

    always_ff @(posedge clk_i) begin
      if (instr_skid_en) begin
        instr_skid_bp_taken_q <= predict_branch_taken;
        instr_skid_data_q     <= fetch_rdata;
        instr_skid_addr_q     <= fetch_addr;
      end
    end

    brq_ifu_branch_predict branch_predict_i (
      .clk_i                  ( clk_i                    ),
      .rst_ni                 ( rst_ni                   ),
      .fetch_rdata_i          ( fetch_rdata              ),
      .fetch_pc_i             ( fetch_addr               ),
      .fetch_valid_i          ( fetch_valid              ),

      .predict_branch_taken_o ( predict_branch_taken_raw ),
      .predict_branch_pc_o    ( predict_branch_pc        )
    );

    // If there is an instruction in the skid buffer there must be no branch prediction.
    // Instructions are only placed in the skid after they have been predicted to be a taken branch
    // so with the skid valid any prediction has already occurred.
    // Do not branch predict on instruction errors.
    assign predict_branch_taken = predict_branch_taken_raw & ~instr_skid_valid_q & ~fetch_err;

    // pc_set_i takes precendence over branch prediction
    assign predicted_branch = predict_branch_taken & ~pc_set_i;

    assign if_instr_valid   = fetch_valid | instr_skid_valid_q;
    assign if_instr_rdata   = instr_skid_valid_q ? instr_skid_data_q : fetch_rdata;
    assign if_instr_addr    = instr_skid_valid_q ? instr_skid_addr_q : fetch_addr;

    // Don't branch predict on instruction error so only instructions without errors end up in the
    // skid buffer.
    assign if_instr_err     = ~instr_skid_valid_q & fetch_err;
    assign instr_bp_taken_d = instr_skid_valid_q ? instr_skid_bp_taken_q : predict_branch_taken;

    assign fetch_ready = id_in_ready_i & ~stall_dummy_instr & ~instr_skid_valid_q;

    assign instr_bp_taken_o = instr_bp_taken_q;


  end else begin : g_no_ifu_branch_predictor
    assign instr_bp_taken_o     = 1'b0;
    assign predict_branch_taken = 1'b0;
    assign predicted_branch     = 1'b0;
    assign predict_branch_pc    = 32'b0;

    assign if_instr_valid = fetch_valid;
    assign if_instr_rdata = fetch_rdata;
    assign if_instr_addr  = fetch_addr;
    assign if_instr_err   = fetch_err;
    assign fetch_ready = id_in_ready_i & ~stall_dummy_instr;
  end

  


endmodule
