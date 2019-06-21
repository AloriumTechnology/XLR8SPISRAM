# XLR8SPISRAM RTL

This directory contains the FPGA logic for the XLR8SPISRAM, which consists of a SPI XB, the SRAM control XB, and a SPI SRAM control driver XB to demonstrate the functionality of the SRAM control XB.

In a custom solution, the SPI SRAM control driver should not be included, it is ONLY meant as a demonstration of the functionality.

The following files are of note:

**xlr8_spi_ram_ctrl.v** - Contains the RTL for the SPI RAM control module, directing the SPI XB to communicate with an attached SPI RAM chip, and can be included in custom OpenXLR8 projects wishing to include SPI RAM functionality.

**spi_ram_drv.v** - Contains RTL for the driver which demonstrates functionality of the SPI RAM control XB, this should not be included in custom projects.

**xb_adr_pack.vh** - Contains the address defines for the AVR to communicate with the OpenXLR8 build.

**openxlr8.v** - Instantiates the SPI XB, the SPI RAM control XB, and the SPI RAM control driver XB, and connects them together.
