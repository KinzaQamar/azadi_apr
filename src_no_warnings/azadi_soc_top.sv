 
module azadi_soc_top 
(
  input clk_i,
  input rst_ni,

  input  logic [32:0] gpio_i,
  output logic [32:0] gpio_o,
  output logic [32:0] gpio_oe,

  // jtag interface 
  input  logic       jtag_tck_i,
  input  logic       jtag_tms_i,
  input  logic       jtag_trst_ni,
  input  logic       jtag_tdi_i,
  output logic       jtag_tdo_o,

  // uart-periph interface
  output logic       uart_tx,
  input  logic       uart_rx,

  // PWM interface  

  output logic       pwm_o,
  output logic       pwm_o_2,

  // SPI interface

  output logic    [`SPI_SS_NB-1:0] ss_o,        
  output logic                     sclk_o,      
  output logic                     sd_o,       
  input  logic                     sd_i,

  // i2c interface 

  //input  logic scl_pad_i,
  //output logic scl_pad_o,
  //output logic scl_padoen_o,

  //input  logic sda_pad_i,
  //output logic sda_pad_o,
  //output logic sda_padoen_o 

);
  localparam logic [31:0] JTAG_ID = {
      4'h0,     // Version
      16'h4F54, // Part Number: "OT"
      11'h426,  // Manufacturer Identity: Google
      1'b1      // (fixed)
    };

  localparam logic DirectDmiTap = 1'b0;

  logic system_rst_ni;
  wire [32:0] gpio_in;
  wire [32:0] gpio_out;
  
  assign gpio_in = gpio_i;
  assign gpio_o = gpio_out; 

  logic         instr_valid;
  logic [11:0]  tlul_addr;
  logic         req_i;
  logic [31:0]  tlul_data;
  logic dbg_req;
  logic dbg_rst;


//end 
// end here        
  tlul_pkg::tl_h2d_t ifu_to_xbar;
  tlul_pkg::tl_d2h_t xbar_to_ifu;
  tlul_pkg::tl_h2d_t xbar_to_iccm;
  tlul_pkg::tl_d2h_t iccm_to_xbar;

  tlul_pkg::tl_h2d_t lsu_to_xbar;
  tlul_pkg::tl_d2h_t xbar_to_lsu;

  tlul_pkg::tl_h2d_t xbar_to_dccm;
  tlul_pkg::tl_d2h_t dccm_to_xbar;

  tlul_pkg::tl_h2d_t xbarm_to_xbarp;
  tlul_pkg::tl_d2h_t xbarp_to_xbarm;

  tlul_pkg::tl_h2d_t xbarp_to_gpio;
  tlul_pkg::tl_d2h_t gpio_to_xbarp;

  tlul_pkg::tl_h2d_t dm_to_xbar;
  tlul_pkg::tl_d2h_t xbar_to_dm;

  tlul_pkg::tl_h2d_t dbgrom_to_xbar;
  tlul_pkg::tl_d2h_t xbar_to_dbgrom;

  tlul_pkg::tl_h2d_t plic_req;
  tlul_pkg::tl_d2h_t plic_resp;

  tlul_pkg::tl_h2d_t xbar_to_uart;
  tlul_pkg::tl_d2h_t uart_to_xbar;

  tlul_pkg::tl_h2d_t xbar_to_timer;
  tlul_pkg::tl_d2h_t timer_to_xbar;

  tlul_pkg::tl_h2d_t xbar_to_pwm;
  tlul_pkg::tl_d2h_t pwm_to_xbar;

  tlul_pkg::tl_h2d_t xbar_to_spi;
  tlul_pkg::tl_d2h_t spi_to_xbar;

  //tlul_pkg::tl_h2d_t xbar_to_i2c;
  //tlul_pkg::tl_d2h_t i2c_to_xbar;

  // interrupt vector
  logic [60:0] intr_vector;

  // Interrupt source list 
  logic [31:0] intr_gpio;
  logic        intr_uart0_tx_watermark;
  logic        intr_uart0_rx_watermark;
  logic        intr_uart0_tx_empty;
  logic        intr_uart0_rx_overflow;
  logic        intr_uart0_rx_frame_err;
  logic        intr_uart0_rx_break_err;
  logic        intr_uart0_rx_timeout;
  logic        intr_uart0_rx_parity_err;
  logic        intr_req;
  logic        intr_spi;
 // logic        intr_i2c;
  logic        intr_srx;
  logic        intr_stx;
  logic        intr_timer;

  assign intr_vector = { 
      intr_srx,
      intr_stx,
    //  intr_i2c, 
      intr_gpio,
      intr_uart0_rx_parity_err,
      intr_uart0_rx_timeout,
      intr_uart0_rx_break_err,
      intr_uart0_rx_frame_err,
      intr_uart0_rx_overflow,
      intr_uart0_tx_empty,
      intr_uart0_rx_watermark,
      intr_uart0_tx_watermark,
      intr_spi,
      1'b0
  };

// jtag interface 

  jtag_pkg::jtag_req_t jtag_req;
  jtag_pkg::jtag_rsp_t jtag_rsp;
  logic unused_jtag_tdo_oe_o;

  assign jtag_req.tck    = jtag_tck_i;
  assign jtag_req.tms    = jtag_tms_i;
  assign jtag_req.trst_n = jtag_trst_ni;
  assign jtag_req.tdi    = jtag_tdi_i;
  assign jtag_tdo_o      = jtag_rsp.tdo;
  assign unused_jtag_tdo_oe_o = jtag_rsp.tdo_oe;


brq_core_top #(
    .PMPEnable        (1'b0),
    .PMPGranularity   (0), 
    .PMPNumRegions    (0), 
    .MHPMCounterNum   (0), 
    .MHPMCounterWidth (40), 
    .RV32E            (1'b0), 
    .RV32M            (brq_pkg::RV32MSlow), 
    .RV32B            (brq_pkg::RV32BNone), 
    .RegFile          (brq_pkg::RegFileFF), 
    .BranchTargetALU  (1'b0), 
    .WritebackStage   (1'b1), 
    .ICache           (1'b0), 
    .ICacheECC        (1'b0), 
    .BranchPredictor  (1'b0), 
    .DbgTriggerEn     (1'b1), 
    .DbgHwBreakNum    (2), 
    .Securebrq        (1'b0),
    .DmHaltAddr       (tl_main_pkg::ADDR_SPACE_DEBUG_ROM + 32'h 800), 
    .DmExceptionAddr  (tl_main_pkg::ADDR_SPACE_DEBUG_ROM + dm::ExceptionAddress) 
) u_top (
    .clk_i (clk_i),
    .rst_ni (system_rst_ni),

  // instruction memory interface 
    .tl_i_i (xbar_to_ifu),
    .tl_i_o (ifu_to_xbar),

  // data memory interface 
    .tl_d_i (xbar_to_lsu),
    .tl_d_o (lsu_to_xbar),

    .test_en_i   (1'b0),     // enable all clk_i gates for testing

    .hart_id_i   (32'b0), 
    .boot_addr_i (32'h20000000),

        // Interrupt inputs
    .irq_software_i (1'b0),
    .irq_timer_i    (intr_timer),
    .irq_external_i (intr_req),
    .irq_fast_i     (1'b0),
    .irq_nm_i       (1'b0),       // non-maskeable interrupt

    // Debug Interface
    .debug_req_i    (dbg_req),
        // CPU Control Signals
    .fetch_enable_i (1'b1),
    .alert_minor_o  (),
    .alert_major_o  (),
    .core_sleep_o   ()
);

// Debug module

  rv_dm #(
  .NrHarts(1),
  .IdcodeValue(JTAG_ID),
  .DirectDmiTap (DirectDmiTap)
  ) debug_module (
  .clk_i(clk_i),       // clk_i
  .rst_ni(rst_ni),      // asynchronous reset active low, connect PoR
                                          // here, not the system reset
  .testmode_i(),
  .ndmreset_o(dbg_rst),  // non-debug module reset
  .dmactive_o(),  // debug module is active
  .debug_req_o(dbg_req), // async debug request
  .unavailable_i(1'b0), // communicate whether the hart is unavailable
                                            // (e.g.: power down)

  // bus device with debug memory, for an execution based technique
  .tl_d_i(dbgrom_to_xbar),
  .tl_d_o(xbar_to_dbgrom),

  // bus host, for system bus accesses
  .tl_h_o(dm_to_xbar),
  .tl_h_i(xbar_to_dm),

  .jtag_req_i(jtag_req),
  .jtag_rsp_o(jtag_rsp)
);



// main xbar module
  tl_xbar_main main_swith (
  .clk_i         (clk_i),
  .rst_ni        (system_rst_ni),

  // Host interfaces
  .tl_brqif_i         (ifu_to_xbar),
  .tl_brqif_o         (xbar_to_ifu),
  .tl_brqlsu_i        (lsu_to_xbar),
  .tl_brqlsu_o        (xbar_to_lsu),
  .tl_dm_sba_i        (dm_to_xbar),
  .tl_dm_sba_o        (xbar_to_dm),

  // Device interfaces
  .tl_iccm_o          (xbar_to_iccm),
  .tl_iccm_i          (iccm_to_xbar),
  .tl_debug_rom_o     (dbgrom_to_xbar),
  .tl_debug_rom_i     (xbar_to_dbgrom),
  .tl_dccm_o          (xbar_to_dccm),
  .tl_dccm_i          (dccm_to_xbar),
  .tl_flash_ctrl_o    (),
  .tl_flash_ctrl_i    (),
  .tl_timer0_o        (xbar_to_timer),
  .tl_timer0_i        (timer_to_xbar),
  .tl_timer1_o        (),
  .tl_timer1_i        (),
  .tl_timer2_o        (),
  .tl_timer2_i        (),
  .tl_timer3_o        (),
  .tl_timer3_i        (),
  .tl_timer4_o        (),
  .tl_timer4_i        (),
  .tl_plic_o          (plic_req),
  .tl_plic_i          (plic_resp),
  .tl_xbar_peri_o     (xbarm_to_xbarp),
  .tl_xbar_peri_i     (xbarp_to_xbarm),

  .scanmode_i         ()
);

// dummy data memory

data_mem dccm(
  .clk_i    (clk_i),
  .rst_ni    (system_rst_ni),

// tl-ul insterface
  .tl_d_i   (xbar_to_dccm),
  .tl_d_o   (dccm_to_xbar)
);

rv_timer timer0(
  .clk_i  (clk_i),
  .rst_ni (system_rst_ni),

  .tl_i   (xbar_to_timer),
  .tl_o   (timer_to_xbar),

  .intr_timer_expired_0_0_o (intr_timer)
);


//peripheral xbar

xbar_periph periph_switch (
  .clk_i         (clk_i),
  .rst_ni        (system_rst_ni),

  // Host interfaces
  .tl_xbar_main_i     (xbarm_to_xbarp),
  .tl_xbar_main_o     (xbarp_to_xbarm),

  // Device interfaces
  .tl_uart0_o         (xbar_to_uart),
  .tl_uart0_i         (uart_to_xbar),
  .tl_uart1_o         (),
  .tl_uart1_i         (),
  .tl_spi0_o          (xbar_to_spi),
  .tl_spi0_i          (spi_to_xbar),
  .tl_spi1_o          (),
  .tl_spi1_i          (),
  .tl_spi2_o          (),
  .tl_spi2_i          (),
  .tl_pwm_o           (xbar_to_pwm),
  .tl_pwm_i           (pwm_to_xbar),
  .tl_gpio_o          (xbarp_to_gpio),
  .tl_gpio_i          (gpio_to_xbarp),
  .tl_i2c0_o          (),
 .tl_i2c0_i          (),
  .tl_i2c1_o          (),
  .tl_i2c1_i          (),
  .tl_can0_o          (),
  .tl_can0_i          (),
  .tl_can1_o          (),
  .tl_can1_i          (),
  .tl_adc_o           (),
  .tl_adc_i           (),
  .tl_qspi_o          (),
  .tl_qspi_i          (),

  .scanmode_i         ()
);


// PWM module

pwm_top u_pwm(

  .clk_i   (clk_i),
  .rst_ni  (system_rst_ni),

  .tl_i    (xbar_to_pwm),
  .tl_o    (pwm_to_xbar),


  .pwm_o   (pwm_o),
  .pwm_o_2 (pwm_o_2)
);


// spi module 

spi_top u_spi_host(

  .clk_i       (clk_i),
  .rst_ni      (system_rst_ni),

  .tl_i        (xbar_to_spi),
  .tl_o        (spi_to_xbar),

  // SPI signals                  
  .intr_rx_o   (intr_srx),
  .intr_tx_o   (intr_stx),                   
  .ss_o        (ss_o),         
  .sclk_o      (sclk_o),       
  .sd_o        (sd_o),       
  .sd_i        (sd_i)
);


//GPIO module
 gpio GPIO (
  .clk_i          (clk_i),
  .rst_ni         (system_rst_ni),

  // Below Regster interface can be changed
  .tl_i           (xbarp_to_gpio),
  .tl_o           (gpio_to_xbarp),

  .cio_gpio_i     (gpio_in),
  .cio_gpio_o     (gpio_out),
  .cio_gpio_en_o  (gpio_oe),

  .intr_gpio_o    (intr_gpio )  
);


instr_mem_top iccm (
  .clk_i      (clk_i),
  .rst_ni      (system_rst_ni),

  .req        (req_i),
  .addr       (tlul_addr),
  .wdata      (),//iccm_cntrl_data
  .rdata      (tlul_data),
  .rvalid     (instr_valid),
  .we         ()//iccm_cntrl_we
);

 tlul_sram_adapter #(
  .SramAw       (12),
  .SramDw       (32), 
  .Outstanding  (2),  
  .ByteAccess   (1),
  .ErrOnWrite   (0),  // 1: Writes not allowed, automatically error
  .ErrOnRead    (0)   // 1: Reads not allowed, automatically error  

) inst_mem (
    .clk_i     (clk_i),
    .rst_ni    (system_rst_ni),
    .tl_i      (xbar_to_iccm),
    .tl_o      (iccm_to_xbar), 
    .req_o     (req_i),
    .gnt_i     (1'b1),
    .we_o      (),
    .addr_o    (tlul_addr),
    .wdata_o   (),
    .wmask_o   (),
    .rdata_i   ((system_rst_ni) ? tlul_data: '0),
    .rvalid_i  (instr_valid),
    .rerror_i  (2'b0)
    );

rstmgr reset_manager(
  .clk_i(clk_i),
  .rst_ni(rst_ni),
  .ndmreset (dbg_rst),
  .sys_rst_ni(system_rst_ni)
);


rv_plic intr_controller (
  .clk_i(clk_i),
  .rst_ni(system_rst_ni),

  // Bus Interface (device)
  .tl_i (plic_req),
  .tl_o (plic_resp),

  // Interrupt Sources
  .intr_src_i (intr_vector),

  // Interrupt notification to targets
  .irq_o (intr_req),
  .irq_id_o(),

  .msip_o()
);

uart u_uart0(
  .clk_i                   (clk_i             ),
  .rst_ni                  (system_rst_ni     ),

  // Bus Interface
  .tl_i                    (xbar_to_uart      ),
  .tl_o                    (uart_to_xbar      ),

  // Generic IO
  .cio_rx_i                (uart_rx           ),
  .cio_tx_o                (uart_tx           ),
  .cio_tx_en_o             (                  ),

  // Interrupts
  .intr_tx_watermark_o     (intr_uart0_tx_watermark ),
  .intr_rx_watermark_o     (intr_uart0_rx_watermark ),
  .intr_tx_empty_o         (intr_uart0_tx_empty     ),
  .intr_rx_overflow_o      (intr_uart0_rx_overflow  ),
  .intr_rx_frame_err_o     (intr_uart0_rx_frame_err ),
  .intr_rx_break_err_o     (intr_uart0_rx_break_err ),
  .intr_rx_timeout_o       (intr_uart0_rx_timeout   ),
  .intr_rx_parity_err_o    (intr_uart0_rx_parity_err) 
);

//i2c_master_top I2C (
  //.clk_i           (clk_i ),
  //.rst_ni          (system_rst_ni),

  //.tl_i            (xbar_to_i2c),
//  .tl_o            (i2c_to_xbar),

  // i2c interface
  //.intr_o          (intr_i2c),

  //.scl_pad_i       (scl_pad_i),
  //.scl_pad_o       (scl_pad_o),
  //.scl_padoen_o    (scl_padoen_o),

  //.sda_pad_i       (sda_pad_i),
  //.sda_pad_o       (sda_pad_o),
  //.sda_padoen_o    (sda_padoen_o)
//);

endmodule
