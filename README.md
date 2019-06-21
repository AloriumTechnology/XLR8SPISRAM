# XLR8SPISRAM Library

This library provides access to a SPI SRAM control XB, allowing hardware control of an attached SPI SRAM.

Including the library will give access to the following functions, accessed via the singleton **XLR8SPISRAM** class object:

- byte_mode() - Sets the SRAM control to Byte Mode, where each byte of data (read or write) is preceded by a 1 byte command, and 2 or 3 bytes of address, so overhead is very high. This is the default mode.
- page_mode() - Sets the SRAM control to Page Mode, which allows for consecutive reads/writes within a page (32 bytes) of memory.  First read/write requires the same command then 2/3 bytes of address, but then each successive read/write causes the SRAM address to increment by one, wrapping at the top of a page back to the bottom.
- sequential_mode() - Sets the SRAM control to Sequential Mode, which is similar to Page mode, but allows access to the entire memory array.
- clock_divider() - Sets the SPI speed as in ATMEGA328 spec (default 100, clk/2, fastest).
- extended_address_enable() - Enable extended address (disabled by default). This is used for SPI SRAM chips which are large and require 3 bytes of address.
- extended_address_disable() - Disable extended address (disabled by default). This is used for most SPI SRAM chips which only require 2 bytes of address.

The library includes an example called **spi_sram_ctrl**, which demonstrates the functionality of the SPI SRAM control XB by using the SPI SRAM control driver XB. For normal operation users will access the SPI SRAM via the control library, this example is just for demonstration purposes.
