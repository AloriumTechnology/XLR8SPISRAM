/*
 * Copyright (c) 2019 Alorium Technology
 * Bryan Craker, info@aloriumtech.com
 *
 * SPI SRAM Control Library for XLR8.
 *
 * MIT License
 */

#ifndef _XLR8SPISRAM_H_INCLUDED
#define _XLR8SPISRAM_H_INCLUDED

// Redefine the SPI clock division codes from the SPI library
#define SPI_CLOCK_DIV4 0x00
#define SPI_CLOCK_DIV16 0x01
#define SPI_CLOCK_DIV64 0x02
#define SPI_CLOCK_DIV128 0x03
#define SPI_CLOCK_DIV2 0x04
#define SPI_CLOCK_DIV8 0x05
#define SPI_CLOCK_DIV32 0x06
//#define SPI_CLOCK_DIV64 0x07

// control reg bits: [7:6] reserved
//                   [5:4] sram mode (byte=00; page=10; seq=01)
//                   [3:1] spi_speed per ATMEGA328 spec (100=fastest)
//                   [0]   extended address enable
#define XLR8SPISRAMMEMCR _SFR_MEM8(0xF0)

class XLR8SPISRAM_Class {

public:

  XLR8SPISRAM_Class() {}

  ~XLR8SPISRAM_Class() {}

  // Default operation is Byte Mode (00) where each byte of data
  // (read or write) is preceded by a 1 byte command, and 2 or
  // 3 bytes of address, so overhead is very high.
  void byte_mode() {
    XLR8SPISRAMMEMCR &= 0x0F;
  }

  // Page Mode (10) allows for consecutive reads/writes within
  // a page (32 bytes) of memory.  First read/write requires the
  // same command then 2/3 bytes of address, but then each
  // successive read/write causes the SRAM address to increment by
  // one, wrapping at the top of a page back to the bottom.
  void page_mode() {
    XLR8SPISRAMMEMCR = (XLR8SPISRAMMEMCR & 0x0F) | 0x20;
  }

  // Sequential Mode (01) is similar to Page mode, but allows
  // access to the entire memory array.
  void sequential_mode() {
    XLR8SPISRAMMEMCR = (XLR8SPISRAMMEMCR & 0x0F) | 0x10;
  }

  // SPI speed as in ATMEGA328 spec (default 100, clk/2, fastest).
  void clock_divider(uint8_t divider) {
    XLR8SPISRAMMEMCR = (XLR8SPISRAMMEMCR & 0x31) | ((uint8_t)(divider << 1));
  }

  // Enable extended address (disabled by default)
  void extended_address_enable() {
    XLR8SPISRAMMEMCR |= 0x01;
  }

  // Disable extended address (disabled by default)
  void extended_address_disable() {
    XLR8SPISRAMMEMCR &= 0x3E;
  }

private:

};

extern XLR8SPISRAM_Class XLR8SPISRAM;

#endif
