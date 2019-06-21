///////////////////////////////////////////////////////////////////
//=================================================================
//  Copyright (c) Alorium Technology 2019
//  ALL RIGHTS RESERVED
//  $Id:  $
//=================================================================
//
// File name:  : xlr8_spi_ram_ctrl.v
// Author      : Mike Berry
// Description : Implementation of a memory controller for use with Microchip
//               SPI-based Serial SRAM chip, and the Alorium SPI XB.  This
//               module acts as a shim that sits in front of the SPI XB,
//               and provides an intuitive user interface for configuring,
//               reading, and writing the Microchip SRAM parts.
//
//               The SPI XB has as its interface Alorium's standard dbus
//               interface, so this module will drive the SPI's dbus pins.
//
//               The user interface consists of the following:
//
//               Inputs:
//               addr[23:0]     - up to 24 bits of address
//               w_data[7:0]    - one byte of write data
//               write_req      - strobe to initiate a write command
//               read_req       - strobe to initiate a read command
//               last           - strobe to indicate last command (page/sequential)
//
//               Outputs:
//               r_data[7:0]    - one bye of read data
//               r_data_valid   - read data valid
//               req_rdy        - indicates end of command, ready for next
//
//               Control Register
//                 [5:4] - sram_mode (byte=00; page=10; seqential=01)
//                 [3:1] - spi_speed as in ATMEGA328 spec (default 100, clk/2, fastest)
//                 [0]   - extended address enable (default is 0)
//
//               Default operation is Byte Mode (00) where each byte of data
//               (read or write) is preceded by a 1 byte command, and 2 or
//               3 bytes of address, so overhead is very high.
//
//               Page Mode (10) allows for consecutive reads/writes within
//               a page (32 bytes) of memory.  First read/write requires the
//               same command then 2/3 bytes of address, but then each
//               successive read/write causes the SRAM address to increment by
//               one, wrapping at the top of a page back to the bottom.
//
//               Sequential Mode (01) is similar to Page mode, but allows
//               access to the entire memory array.
//
//               Usage would be as follows:
//
//                 - configure via control register from software
//                 - wait for req_rdy to go high
//                 - define addr, w_data (for a write), and provide write_req
//                   or read_req strobe (and last strobe if it's the final
//                   access in page or sequential mode)
//                 - wait for r_data_valid before reading r_data
//                 - repeat
//
//               Note that you can drive addr, w_data, and the request strobes
//               prior to seeing a req_rdy; the logic will grab the inputs as
//               soon as req_rdy goes high, then immediately drop req_rdy,
//               indicating that a command has been initiated.
// 
//=================================================================
///////////////////////////////////////////////////////////////////

module xlr8_spi_ram_ctrl
  #(
   parameter MEMCR_ADDR      = 8'h00,
   parameter spi_ram_SPCR_Address = 8'h00, // should be defined in spi_ram_adr_pack.vh
   parameter spi_ram_SPSR_Address = 8'h00, // should be defined in spi_ram_adr_pack.vh
   parameter spi_ram_SPDR_Address = 8'h00  // should be defined in spi_ram_adr_pack.vh
  )
  (
   // Input/Ouput definitions for the module. These are standard and
   // while other ports could be added, these are required.
   //  
   // Clock and Reset
   input        clk, //       Clock
   input        rstn, //      Reset
   input        clken, //     Clock Enable
   // I/O 
   input [7:0]  dbus_in, //   Data Bus Input
   output [7:0] dbus_out, //  Data Bus Output
   output       io_out_en, // IO Output Enable
   // DM
   input [7:0]  ramadr, //    RAM Address
   input        ramre, //     RAM Read Enable
   input        ramwe, //     RAM Write Enable
   input        dm_sel, //    DM Select

   // data/control bus to SPI XB, mimics dbus
   output logic [7:0] spi_ramadr,         // Register Address to SPI block
   output logic       spi_ramre,          // Read Enable to SPI block
   output logic       spi_ramwe,          // Write Enable to SPI block
   output logic       spi_dm_sel,         // DM Select to SPI block
   output logic [7:0] spi_dbus_in,        // Data Bus Input to SPI block
   input  logic [7:0] spi_dbus_out,       // Data Bus Output from SPI block

   // user interface
   input logic [23:0] addr,         // SRAM address
   input logic [7:0]  w_data,       // write data
   input logic        w_req,        // write request strobe
   input logic        r_req,        // read request strobe
   input logic        last,         // strobe to indicate last command (page/seq)

   output logic [7:0] r_data,       // read data
   output logic       r_data_valid, // read data valid
   output logic       req_rdy,      // indicates end of command, ready for next
   output logic       cs_out        // chip select; connect to SPI SRAM
  );
  
  //======================================================================

  logic memcr_sel;
  logic memcr_we;
  logic memcr_re;
  logic [7:0] memcr_data;

  logic        r_req_sync;
  logic        w_req_sync;
  logic [23:0] addr_sync;
  logic [7:0]  w_data_sync;
  logic        last_sync;

  logic [1:0]  sram_mode;
  logic [2:0]  spi_speed;
  logic        ext_addr_en;

  logic        config_update; // flag to update the SPI, SRAM configs
  logic        config_update_hold; // flag to update the SPI, SRAM configs
  logic [3:0]  state;
  logic [3:0]  prev_state;
  logic [1:0]  xfer_state;
  logic [7:0]  spi_r_data;
  logic        spi_xfer_go;
  logic        spi_xfer_run;
  logic        spi_xfer_done;
  logic        spi_grab_r_data;
  logic        multi_w_r;
  
  
  //======================================================================
  //  Control select
  //
  // For each register interface, do control select based on address
  assign memcr_sel = dm_sel && (ramadr == MEMCR_ADDR);
  assign memcr_we  = memcr_sel && ramwe;
  assign memcr_re  = memcr_sel && ramre;
  
  // Mux the data and enable outputs
  assign dbus_out =  ({8{memcr_sel}} & memcr_data);
  assign io_out_en = memcr_re;

  // End, Control Select
  //----------------------------------------------------------------------
  

  //======================================================================
  // Load write data from AVR core into registers

  assign sram_mode   = memcr_data[5:4];
  assign spi_speed   = memcr_data[3:1];
  assign ext_addr_en = memcr_data[0];
  
  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          // default to byte mode, clk/2, short addr
          memcr_data <= 8'b00001000;
          config_update <= 1'b0; // flag to start config state machine
        end
      else if (memcr_we)
        begin
          memcr_data <= dbus_in;
          config_update <= 1'b1; // set flag to start config state machine
        end
      else
        begin
          config_update <= 1'b0; // we'll hold the value later in case the update is delayed
        end
    end // always @ (posedge clk or negedge rstn)

  // End, Load write data


  // grab addr/data inputs on req strobe
  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          // reset stuff
        end
      else
        begin
          if (w_req)
            begin
              addr_sync   <= addr;
              w_data_sync <= w_data;
              last_sync   <= last;
            end
          else if (r_req)
            begin
              addr_sync   <= addr;
              last_sync   <= last;
            end
        end
    end

  // State machine to control accesses to the SPI block.  This deals with the
  // different transaction types for the SPI SRAM; namely, configuration,
  // reads, and writes, including managing multiple consecutive reads/writes
  // when the SRAM is in Page or Sequential mode.
  //
  // To manage the SPI transfers themselves, there is a 2nd state machine that
  // gets kicked off from within the main state machine.

  localparam IDLE       = 4'h0;
  localparam CONFIG1    = 4'h1; // update spcr
  localparam CONFIG2    = 4'h2; // update spsr (needed for double-speed SPI)
  localparam CONFIGCMD  = 4'h3; // SRAM command to update status register
  localparam CONFIGDATA = 4'h4; // SRAM data to status register
  localparam READCMD    = 4'h5;
  localparam WRITECMD   = 4'h6;
  localparam RAMADDR3   = 4'h7; // extended address
  localparam RAMADDR2   = 4'h8;
  localparam RAMADDR1   = 4'h9;
  localparam READDATA   = 4'hA;
  localparam WRITEDATA  = 4'hB;

  // Microchip SPI SRAM commands
  localparam SRAM_READ  = 8'h03;
  localparam SRAM_WRITE = 8'h02;
  localparam SRAM_RDSR  = 8'h05;
  localparam SRAM_WRSR  = 8'h01;

  localparam SRAM_PAGE_MODE = 2'b10;
  localparam SRAM_SEQ_MODE  = 2'b01;

  assign spi_dm_sel     = 1'b1; // tie high, and control access via re and we

  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          config_update_hold <= 1'b0;
          r_req_sync         <= 1'b0;
          w_req_sync         <= 1'b0;
          r_data_valid       <= 1'b0;
          r_data             <= 8'h00;
          prev_state         <= IDLE;
          state              <= IDLE;
          req_rdy            <= 1'b0;
          cs_out             <= 1'b1; // active low, so start out inactive
          spi_grab_r_data    <= 1'b0;
          multi_w_r          <= 1'b0;
        end
      else
        begin
          if (config_update)
            config_update_hold <= 1'b1; // grab the update bit and hold until the update happens
          if (r_req)
            r_req_sync <= 1'b1;
          if (w_req)
            w_req_sync <= 1'b1;
          case (state)
            IDLE:
              begin
                prev_state <= IDLE;
                // need to grab the read data if the flag is set
                if (spi_grab_r_data)
                  begin
                    spi_grab_r_data <= 1'b0;
                    r_data <= spi_r_data;
                    r_data_valid <= 1'b1;
                  end
                if (req_rdy && config_update_hold)
                  begin
                    config_update_hold <= 1'b0;
                    req_rdy <= 1'b0; // drop the ready line
                    state <= CONFIG1;
                  end
                else if (req_rdy && (r_req || r_req_sync)) // or the raw input to save a clock
                  begin
                    req_rdy <= 1'b0; // drop the ready line
                    r_data_valid <= 1'b0; // drop the data valid - next xfer about to begin
                    if (multi_w_r)
                      begin
                        state <= READDATA;
                      end
                    else
                      begin
                        state <= READCMD;
                      end
                  end
                else if (req_rdy && (w_req || w_req_sync)) // or the raw input to save a clock
                  begin
                    req_rdy <= 1'b0; // drop the ready line
                    r_data_valid <= 1'b0; // drop the data valid - next xfer about to begin
                    if (multi_w_r)
                      begin
                        state <= WRITEDATA;
                      end
                    else
                      begin
                        state <= WRITECMD;
                      end
                  end
                else
                  begin
                    req_rdy <= 1'b1; // nothing else happening, so set ready bit
                    if (!multi_w_r)
                      cs_out  <= 1'b1; // ...and raise cs_out unless we're in page or seq mode
                    state <= IDLE;
                  end
              end

            CONFIG1: // write SPCR
              begin
                prev_state <= CONFIG1;
                if (spi_xfer_done)
                  state <= CONFIG2;
                else
                  state <= CONFIG1;  // stay here until we hear back from xfer state machine
              end

            CONFIG2: // write SPSR
              begin
                prev_state <= CONFIG2;
                if (spi_xfer_done)
                  state <= CONFIGCMD;
                else
                  state <= CONFIG2;  // stay here until we hear back from xfer state machine
              end

            CONFIGCMD: // send WRSR command to SRAM via SPI to update status reg
              begin
                prev_state <= CONFIGCMD;
                cs_out <= 1'b0; // start a SPI xfer
                if (spi_xfer_done)
                  begin
                    state <= CONFIGDATA;
                  end
              end

            CONFIGDATA: // send config data to SRAM via SPI to update status reg
              begin
                prev_state <= CONFIGDATA;
                if (spi_xfer_done)
                  begin
                    state <= IDLE;
                  end
              end

            READCMD: // send READ cmd to SRAM via SPI
              begin
                prev_state <= READCMD;
                cs_out <= 1'b0; // start a SPI xfer
                if (spi_xfer_done)
                  begin
                    if (ext_addr_en)
                      begin
                        state <= RAMADDR3;
                      end
                    else
                      begin
                        state <= RAMADDR2;
                      end
                  end
              end

            WRITECMD: // send READ cmd to SRAM via SPI
              begin
                prev_state <= WRITECMD;
                cs_out <= 1'b0; // start a SPI xfer
                if (spi_xfer_done)
                  begin
                    if (ext_addr_en)
                      begin
                        state <= RAMADDR3;
                      end
                    else
                      begin
                        state <= RAMADDR2;
                      end
                  end
              end

            RAMADDR3: // send ADDR3 via SPI to SRAM (only for extended addressing)
              begin
                prev_state <= RAMADDR3;
                if (spi_xfer_done)
                  begin
                    state <= RAMADDR2;
                  end
              end

            RAMADDR2: // send ADDR2 via SPI to SRAM
              begin
                prev_state <= RAMADDR2;
                if (spi_xfer_done)
                  begin
                    state <= RAMADDR1;
                  end
              end

            RAMADDR1: // send ADDR1 via SPI to SRAM
              begin
                prev_state <= RAMADDR1;
                if (spi_xfer_done)
                  begin
                    if (r_req_sync)
                      begin
                        r_req_sync <= 1'b0; // we're done with this until the next r_req
                        state <= READDATA;
                      end
                    else if (w_req_sync)
                      begin
                        w_req_sync <= 1'b0; // we're done with this until the next w_req
                        state <= WRITEDATA;
                      end
                    else // should never get here...
                      begin
                        state <= IDLE;
                      end
                  end
              end

            READDATA: // data via SPI from SRAM
              begin
                prev_state <= READDATA;
                req_rdy <= 1'b0; // be sure to drop rdy when we're doing multi-reads
                if (spi_grab_r_data)
                  begin
                    spi_grab_r_data <= 1'b0;
                    r_data <= spi_r_data;
                    r_data_valid <= 1'b1;
                  end
                if (spi_xfer_done)
                  begin
                    r_data_valid <= 1'b0; // drop the valid; another read about to happen
                    spi_grab_r_data <= 1'b1; // flag that we need to grab read data on next clk
                    r_req_sync <= 1'b0; // we're done with this until the next r_req
                    if (((sram_mode == SRAM_PAGE_MODE) ||
                         (sram_mode == SRAM_SEQ_MODE)) &&
                        !last_sync)
                      begin
                        multi_w_r <= 1;
                        req_rdy <= 1'b1;
                        if (r_req) // use the input directly to avoid a cycle of latency
                          state <= READDATA;
                        else
                          state <= IDLE;
                      end
                    else
                      begin
                        multi_w_r <= 0;
                        state <= IDLE;
                      end
                  end
              end

            WRITEDATA: // data via SPI to SRAM
              begin
                prev_state <= WRITEDATA;
                req_rdy <= 1'b0; // be sure to drop rdy when we're doing multi-writes
                if (spi_xfer_done)
                  begin
                    w_req_sync <= 1'b0; // we're done with this until the next w_req
                    if (((sram_mode == SRAM_PAGE_MODE) ||
                         (sram_mode == SRAM_SEQ_MODE)) &&
                        !last_sync)
                      begin
                        multi_w_r <= 1; // needed if we end up back at IDLE
                        req_rdy <= 1'b1;
                        if (w_req) // use the input directly to avoid a cycle of latency
                          state <= WRITEDATA;
                        else
                          state <= IDLE;
                      end
                    else
                      begin
                        multi_w_r <= 0;
                        state <= IDLE;
                      end
                  end
              end

            default:
              begin
                prev_state <= IDLE;
                state <= IDLE;
              end
          endcase
        end // if (!rstn)
    end // always

  // State machine to control a single SPI transfer (either read or write).
  // This state machine is called from within the larger state machine that is
  // managing the transactions to/from the connected SPI RAM.

  localparam XFER_IDLE      = 2'h0;
  localparam XFER_READ_SPSR = 2'h1;
  localparam XFER_POLL_SPIF = 2'h2;
  localparam XFER_READ_DBUS = 2'h3;
  localparam SPIF_BIT       = 7;

  // Start the xfer state machine when relevant state transitions in the main
  // state machine occur
  assign spi_xfer_go = ((state == CONFIG1    && prev_state != CONFIG1)    ||
                        (state == CONFIG2    && prev_state != CONFIG2)    ||
                        (state == CONFIGCMD  && prev_state != CONFIGCMD)  ||
                        (state == CONFIGDATA && prev_state != CONFIGDATA) ||
                        (state == READCMD    && prev_state != READCMD)    ||
                        (state == WRITECMD   && prev_state != WRITECMD)   ||
                        (state == RAMADDR3   && prev_state != RAMADDR3)   ||
                        (state == RAMADDR2   && prev_state != RAMADDR2)   ||
                        (state == RAMADDR1   && prev_state != RAMADDR1)   ||
                        (state == READDATA   && prev_state != READDATA)   ||
                        (state == WRITEDATA  && prev_state != WRITEDATA));

  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          spi_ramwe          <= 1'b0;
          spi_ramre          <= 1'b0;
          spi_ramadr         <= 8'h00;
          spi_dbus_in        <= 8'h00;
          spi_xfer_run       <= 1'b0;
          xfer_state         <= XFER_IDLE;
          spi_r_data         <= 8'h00;
          spi_xfer_done      <= 1'b0;
        end
      else
        begin
          case (xfer_state)
            XFER_IDLE:
              begin
                spi_xfer_done <= 1'b0; // needed for special case of CONFIG1/CONFIG2 handling
                if (spi_xfer_go)
                  begin
                    // ready to start a transfer
                    spi_xfer_run <= 1'b1;
                    spi_ramwe <= 1'b1;

                    // set the dbus address
                    if (state == CONFIG1)
                      spi_ramadr <= spi_ram_SPCR_Address;
                    else if (state == CONFIG2)
                      spi_ramadr <= spi_ram_SPSR_Address;
                    else
                      spi_ramadr <= spi_ram_SPDR_Address;

                    // define the write data
                    if (state == CONFIG1)
                      spi_dbus_in <= {6'b010100,{spi_speed[1:0]}}; // enable as master, set speed bits
                    else if (state == CONFIG2)
                      spi_dbus_in <= {7'h00,{spi_speed[2]}}; // enable as master, set speed bits
                    else if (state == CONFIGCMD)
                      spi_dbus_in <= SRAM_WRSR; // send WRSR command
                    else if (state == CONFIGDATA)
                      spi_dbus_in <= {{sram_mode[1:0]},6'h00}; // set SRAM mode bits
                    else if (state == READCMD)
                      spi_dbus_in <= SRAM_READ; // send READ command
                    else if (state == WRITECMD)
                      spi_dbus_in <= SRAM_WRITE; // send WRITE command
                    else if (state == RAMADDR3)
                      spi_dbus_in <= addr_sync[23:16]; // upper byte of address
                    else if (state == RAMADDR2)
                      spi_dbus_in <= addr_sync[15:8]; // mid byte of ext address; upper of std addr
                    else if (state == RAMADDR1)
                      spi_dbus_in <= addr_sync[7:0]; // low byte of address
                    else if (state == READDATA)
                      spi_dbus_in <= 8'hFF; // don't care - we're looking for the read data
                    else if (state == WRITEDATA)
                      spi_dbus_in <= w_data_sync; // grab w_data from input

                    xfer_state <= XFER_READ_SPSR;
                  end
                else
                  begin
                    spi_xfer_run  <= 1'b0; // needed for special case of CONFIG1/CONFIG2 handling
                    xfer_state <= XFER_IDLE;
                  end
              end
            XFER_READ_SPSR:
              begin
                spi_ramwe <= 1'b0;
                if (state == CONFIG1 || state == CONFIG2)
                  // special case where we're not actually doing a SPI xfer,
                  // just a SPI register write, so we'll terminate things and go
                  // back to IDLE state
                  begin
                    spi_xfer_done <= 1'b1;
                    xfer_state <= IDLE;
                  end
                else
                  begin
                    spi_ramre <= 1'b1; // immediately start reading SPSR to look for SPIF
                    spi_ramadr <= spi_ram_SPSR_Address;
                    xfer_state <= XFER_POLL_SPIF;
                  end
              end
            XFER_POLL_SPIF:
              begin
                if (spi_dbus_out & (1<<SPIF_BIT))
                  begin
                    spi_ramadr <= spi_ram_SPDR_Address; // do a read of SPDR to clear SPIF
                    spi_xfer_done <= 1'b1; // pre-set this to remove a cycle before next xfer
                    xfer_state <= XFER_READ_DBUS;
                  end
                else
                  begin
                    xfer_state <= XFER_POLL_SPIF; // keep waiting for SPIF bit to set
                  end
              end
            XFER_READ_DBUS:
              begin
                spi_xfer_run <= 1'b0; // transfer complete
                spi_xfer_done <= 1'b0; // reset this - just need it for one clock
                spi_ramre <= 1'b0;
                spi_r_data <= spi_dbus_out;
                xfer_state <= XFER_IDLE;
              end
            default:
              begin
                xfer_state <= IDLE;
              end
          endcase
        end // if (!rstn)
    end // always
  
endmodule

