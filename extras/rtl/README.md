# XLR8 SPI SRAM Controller RTL

This directory contains the FPGA logic for the XLR8 SPI SRAM controller, which consists of a SPI XB, the SRAM control XB, and a SPI SRAM control driver XB to demonstrate the functionality of the SRAM control XB.

## Required Files
The following files are required for using the SPI SRAM Controller XB:

**xlr8_spi_ram_ctrl.v** - Contains the RTL for the SPI RAM control module, directing the SPI XB to communicate with an attached SPI RAM chip, and can be included in custom OpenXLR8 projects wishing to include SPI RAM functionality.

**xb_adr_pack.vh** - Contains the address defines for the AVR to communicate with the OpenXLR8 build.

**openxlr8.v** - Instantiates the SPI XB, the SPI RAM control XB, and the SPI RAM control driver XB, and connects them together.

In addition, you will need to grab the XLR8 SPI XB from this repo:  https://github.com/AloriumTechnology/XLR8SPI

## Demonstration Driver 
We have provided RTL source for a  driver block that can be used for demonstration purposes.  

**spi_ram_drv.v** - Contains RTL for the driver which demonstrates functionality of the SPI RAM control XB, this should not be included in custom projects.

**NOTE:** In your custom solution, the SPI SRAM control driver should **NOT** be included. It is ONLY meant as a demonstration of the functionality.
