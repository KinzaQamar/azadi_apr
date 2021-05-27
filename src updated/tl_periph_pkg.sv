// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// tl_periph package generated by `tlgen.py` tool

package tl_periph_pkg;

  localparam logic [31:0] ADDR_SPACE_UART0 = 32'h 40060000;
  localparam logic [31:0] ADDR_SPACE_UART1 = 32'h 40070000;
  localparam logic [31:0] ADDR_SPACE_SPI0  = 32'h 40080000;
  localparam logic [31:0] ADDR_SPACE_SPI1  = 32'h 40090000;
  localparam logic [31:0] ADDR_SPACE_SPI2  = 32'h 400a0000;
  localparam logic [31:0] ADDR_SPACE_PWM   = 32'h 400b0000;
  localparam logic [31:0] ADDR_SPACE_GPIO  = 32'h 400c0000;
  localparam logic [31:0] ADDR_SPACE_I2C0  = 32'h 400d0000;
  localparam logic [31:0] ADDR_SPACE_I2C1  = 32'h 400e0000;
  localparam logic [31:0] ADDR_SPACE_CAN0  = 32'h 400f0000;
  localparam logic [31:0] ADDR_SPACE_CAN1  = 32'h 40100000;
  localparam logic [31:0] ADDR_SPACE_ADC   = 32'h 40200000;
  localparam logic [31:0] ADDR_SPACE_QSPI  = 32'h 40300000;

  localparam logic [31:0] ADDR_MASK_UART0 = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_UART1 = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_SPI0  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_SPI1  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_SPI2  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_PWM   = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_GPIO  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_I2C0  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_I2C1  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_CAN0  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_CAN1  = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_ADC   = 32'h 0000ffff;
  localparam logic [31:0] ADDR_MASK_QSPI  = 32'h 0000ffff;

  localparam int N_HOST   = 1;
  localparam int N_DEVICE = 13;

  typedef enum int {
    TlUart0 = 0,
    TlUart1 = 1,
    TlSpi0 = 2,
    TlSpi1 = 3,
    TlSpi2 = 4,
    TlPwm = 5,
    TlGpio = 6,
    TlI2C0 = 7,
    TlI2C1 = 8,
    TlCan0 = 9,
    TlCan1 = 10,
    TlAdc = 11,
    TlQspi = 12
  } tl_device_e;

  typedef enum int {
    TlXbarMain = 0
  } tl_host_e;

endpackage