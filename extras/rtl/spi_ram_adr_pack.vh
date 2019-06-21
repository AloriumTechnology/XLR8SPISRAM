//======================================================================
// Filename    : xb_adr_pack.vh
// Author      : Mike Berry
// Description : local registers used only within custom XBs; in
//               particular, these are NOT in the AVR address space
//
// Copyright 2019, Alorium Technology, LLC. All Rights Reserved.
//----------------------------------------------------------------------

//======================================================================
// Enter your allocations here
// Recommendation is to use addresses at or above 0x80
//
localparam spi_ram_SPCR_Address       = 8'h81;
localparam spi_ram_SPSR_Address       = 8'h82;
localparam spi_ram_SPDR_Address       = 8'h83;
