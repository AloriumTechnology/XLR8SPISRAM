///////////////////////////////////////////////////////////////////
//=================================================================
//  Copyright (c) Alorium Technology 2019
//  ALL RIGHTS RESERVED
//  $Id:  $
//=================================================================
//
// File name:  : spi_ram_drv.v
// Author      : Mike Berry
// Description : Test logic to drive the xlr8_spi_ram_ctrl XB for testing
//               purposes.  This could also be used as a design reference for
//               someone developing logic that interfaces to the Alorium SPI
//               ram controller XB.
//
//               The "user" interface is from software via registers connected
//               up via dbus as follows:
//
//               SPIRAMDRVCTL - control register defined as follows:
//                 [7]   - read strobe (always reads 0)
//                 [6]   - write strobe (always reads 0)
//                 [5]   - last bit (required only if RAM is in page or
//                         sequential mode, and then only on the final
//                         transfer) (always reads 0)
//                 [4:2] - reserved
//                 [1]   - req_rdy (read only)
//                 [0]   - rdata_valid (read only)
//
//               SPIRAMDRVADDRH - upper byte of address (R/W register)
//               SPIRAMDRVADDRL - lower byte of address (R/W register)
//                 ** note that the controller XB supports 24 bit addressing
//                 for larger memory parts; this driver only supports 16 bits
//               SPIRAMDRVWDATA - write data (write only register)
//               SPIRAMDRVRDATA - read data (read only register)
//               
//               User defines address (and optionally write data), then writes
//               the control register with the appropriate strobe and if the
//               RAM is in page or seq mode, optionally write the last bit to
//               terminate the page/seq operation.  The driver block will then
//               control the inputs to the controller XB to do the requested
//               operation.
//
// 
//=================================================================
///////////////////////////////////////////////////////////////////

module spi_ram_drv  // NOTE: Change the module name to match your design
  #(
  parameter SPIRAMDRVCTL_ADDR   = 8'h00,
  parameter SPIRAMDRVADDRH_ADDR = 8'h00,
  parameter SPIRAMDRVADDRL_ADDR = 8'h00,
  parameter SPIRAMDRVWDATA_ADDR = 8'h00,
  parameter SPIRAMDRVRDATA_ADDR = 8'h00
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

  // signals connected to SPI Ram controller XB
  input logic [7:0] rdata_in,
  input logic       rdata_valid_in,
  input logic       req_rdy,

  output logic [16:0] addr_out,
  output logic [7:0]  wdata_out,
  output logic        w_req_out,
  output logic        r_req_out,
  output logic        last_out
  );
 
  //======================================================================
  // R/W registers
  logic ctrl_sel;
  logic ctrl_we;
  logic ctrl_re;
  logic [7:0] ctrl_reg;

  logic addrh_sel;
  logic addrh_we;
  logic addrh_re;
  logic [7:0] addrh;

  logic addrl_sel;
  logic addrl_we;
  logic addrl_re;
  logic [7:0] addrl;

  // write-only
  logic wdata_sel;
  logic wdata_we;
  logic [7:0] wdata;

  // read-only
  logic rdata_sel;
  logic rdata_we;
  logic rdata_re;
  logic [7:0] rdata;

  logic read_strobe;
  logic write_strobe;
  logic last_xfer;
  logic read_strobe_hold;
  logic write_strobe_hold;
  logic last_xfer_hold;
  logic rdata_valid;
  logic ignore_valid_in;
  
  //======================================================================
  //  Control select
  //
  // For each register interface, do control select based on address
  assign ctrl_sel = dm_sel && (ramadr == SPIRAMDRVCTL_ADDR);
  assign ctrl_we  = ctrl_sel && ramwe;
  assign ctrl_re  = ctrl_sel && ramre;
  
  assign addrh_sel = dm_sel && (ramadr == SPIRAMDRVADDRH_ADDR);
  assign addrh_we  = addrh_sel && ramwe;
  assign addrh_re  = addrh_sel && ramre;
  
  assign addrl_sel = dm_sel && (ramadr == SPIRAMDRVADDRL_ADDR);
  assign addrl_we  = addrl_sel && ramwe;
  assign addrl_re  = addrl_sel && ramre;
  
  assign wdata_sel = dm_sel && (ramadr == SPIRAMDRVWDATA_ADDR);
  assign wdata_we  = wdata_sel && ramwe;

  assign rdata_sel = dm_sel && (ramadr == SPIRAMDRVRDATA_ADDR);
  assign rdata_we  = rdata_sel && ramwe;
  assign rdata_re  = rdata_sel && ramre;

  // Mux the data and enable outputs

  assign ctrl_reg[1] = req_rdy;
  assign ctrl_reg[0] = rdata_valid;
  assign dbus_out =  ({8{ ctrl_sel  }} & ctrl_reg  ) |
                     ({8{ addrh_sel }} & addrh ) |
                     ({8{ addrl_sel }} & addrl ) |
                     ({8{ rdata_sel }} & rdata     );

  assign io_out_en = ctrl_re  ||
                     addrh_re ||
                     addrl_re ||
                     rdata_re;

  // End, Control Select
  //----------------------------------------------------------------------
  

  //======================================================================
  // Load control register

  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          ctrl_reg[7:2] <= 6'h00;
          read_strobe <= 1'b0;
          write_strobe <= 1'b0;
          last_xfer <= 1'b0;
        end
      else if (ctrl_we)
        begin
          {{read_strobe},{write_strobe},{last_xfer}} <= dbus_in[7:5];
        end
      else
        begin
          {{read_strobe},{write_strobe},{last_xfer}} <= 3'b0; // just do one op per ctrl reg write
        end
    end // always @ (posedge clk or negedge rstn)
  
  // Load addrh register
  always @(posedge clk or negedge rstn) begin
     if (!rstn) begin
       addrh <= 8'h00;
     end
     else if (addrh_we) begin
       addrh <= dbus_in;
     end
  end // always @ (posedge clk or negedge rstn)
  
  // Load addrl register
  always @(posedge clk or negedge rstn) begin
     if (!rstn) begin
       addrl <= 8'h00;
     end
     else if (addrl_we) begin
       addrl <= dbus_in;
     end
  end // always @ (posedge clk or negedge rstn)
  
  // Load wdata register
  always @(posedge clk or negedge rstn) begin
     if (!rstn) begin
       wdata <= 8'h00;
     end
     else if (wdata_we) begin
       wdata <= dbus_in;
     end
  end // always @ (posedge clk or negedge rstn)
  
  //----------------------------------------------------------------------

  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          read_strobe_hold <= 1'b0;
          write_strobe_hold <= 1'b0;
          last_xfer_hold <= 1'b0;
          addr_out <= 8'h00;
          wdata_out <= 8'h00;
          r_req_out <= 1'b0;
          w_req_out <= 1'b0;
          last_out <= 1'b0;
        end
      else
        begin
          if (read_strobe)
            read_strobe_hold <= 1'b1;
          if (write_strobe)
            write_strobe_hold <= 1'b1;
          if (last_xfer)
            last_xfer_hold <= 1'b1;
          if ((read_strobe || read_strobe_hold) && (req_rdy))
            begin
              read_strobe_hold <= 1'b0; // clear the strobe bit and start a transfer
              last_xfer_hold <= 1'b0;   // clear the last bit; if it wasn't set, no harm done
              addr_out <= {{addrh},{addrl}};
              r_req_out <= 1'b1;
              w_req_out <= 1'b0; // can't both be set
              last_out <= last_xfer || last_xfer_hold;
            end
          else if ((write_strobe || write_strobe_hold) && (req_rdy))
            begin
              write_strobe_hold <= 1'b0; // clear the strobe bit and start a transfer
              last_xfer_hold <= 1'b0;   // clear the last bit; if it wasn't set, no harm done
              addr_out <= {{addrh},{addrl}};
              wdata_out <= wdata;
              w_req_out <= 1'b1;
              r_req_out <= 1'b0; // can't both be set
              last_out <= last_xfer || last_xfer_hold;
            end
          else
            begin
              w_req_out <= 1'b0;
              r_req_out <= 1'b0;
            end
        end
    end

  always @(posedge clk or negedge rstn)
    begin
      if (!rstn)
        begin
          ignore_valid_in <= 1'b0; // flag to ignore valid in once rdata read occurs
          rdata_valid <= 1'b0;
          rdata <= 8'h00;
        end
      else 
        begin
          if (r_req_out)
            begin
              ignore_valid_in <= 1'b0; // clear once the next read starts
              rdata_valid <= 1'b0; // clear once the next read starts
            end
          else if (rdata_re) // clear valid, set ignore when we read rdata
            begin
              rdata_valid <= 1'b0;
              ignore_valid_in <= 1'b1;
            end
          else if (rdata_valid_in && !ignore_valid_in)
            begin
              rdata_valid <= 1'b1;
              rdata <= rdata_in;
            end
          else
            begin
              rdata_valid <= 1'b0;
              rdata <= 8'h00;
            end
        end
    end


  
endmodule

