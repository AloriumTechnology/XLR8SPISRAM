//_______________________________________________________________________________
//
// XLR8SPIRAM - test SPI-based ram controller XB
//  An XLR8SPI object is set up to use the default Arduino SPI interface.
//  SCK is pin  7
//  MISO is pin 6
//  MOSI is pin 5
//  SS is pin   4
//
//_______________________________________________________________________________

#include <XLR8SPISRAM.h>

#define SPIRAMDRVCTL    _SFR_MEM8(0xF1)
#define SPIRAMDRVADDRH  _SFR_MEM8(0xF2)
#define SPIRAMDRVADDRL  _SFR_MEM8(0xF3)
#define SPIRAMDRVWDATA  _SFR_MEM8(0xF4)
#define SPIRAMDRVRDATA  _SFR_MEM8(0xF5)

#define VALID 0  // rdata_valid bit in ctrl_reg
#define RDY   1  // req_rdy bit in ctrl_reg

//#define DEBUG // comment out for no debug output

boolean req_rdy;
boolean rdata_valid = 0;
byte    ctl_reg = 0;

int16_t i; // counter for multiple writes/reads
char str[50];
boolean error;

void setup() {

  Serial.begin(115200);
  Serial.println("====");

  byte_mode(512);
  page_mode(32);
  seq_mode(256);
  page_then_byte(16);

}

void loop() {
}

void byte_mode(uint16_t num_iter) {
  sprintf(str,"Begin BYTE mode with %d iterations",num_iter);
  Serial.println(str);
  byte    wdata[num_iter];
  byte    addrl[num_iter];
  byte    rdata[num_iter];

  // byte mode, clk/2, no extended addr
  XLR8SPISRAM.byte_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV2);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = 0x00;

  for (i=0; i <= (num_iter-1); i++) {
    wdata[i] = byte(i+1);
    addrl[i] = SPIRAMDRVADDRL;
    SPIRAMDRVWDATA = wdata[i];
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    SPIRAMDRVCTL = 0x40; // 0x40 is write strobe, last=0
    SPIRAMDRVADDRL ++;
  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");
    }
    Serial.println("=====");
  #endif

  // try slowing down the clock for the read (needed for >8MHz SPI clk)
  XLR8SPISRAM.byte_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV4);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = num_iter-1; // do the reads in a different order - start at the end...
  for (i=(num_iter-1); i >= 0; i--) {
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    SPIRAMDRVCTL = 0x80; // 0x80 is read strobe, last=0
    while (!(SPIRAMDRVCTL & _BV(VALID))) { // wait for data valid
    }
    rdata[i] = SPIRAMDRVRDATA;
    SPIRAMDRVADDRL --;

  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"rdata:       0x%02X",rdata[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");

    }
  #endif // DEBUG

  error = false;
  for (i=0; i <= (num_iter-1); i++) {
    if (wdata[i] != rdata[i]) {
      error = true;
    }
  }
  if (error) {
    Serial.println("ERROR in BYTE mode");
  } else {
    Serial.println("BYTE mode PASSED");
  }
  Serial.println("--");
} // byte_mode       

void page_mode(uint16_t num_iter) {
  byte    wdata[num_iter];
  byte    addrl[num_iter];
  byte    rdata[num_iter];
  sprintf(str,"Begin PAGE mode with %d iterations",num_iter);
  Serial.println(str);

  // page mode, clk/2, no extended addr
  XLR8SPISRAM.page_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV2);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = 0x00;
  addrl[0] = SPIRAMDRVADDRL;

  for (i=0; i <= (num_iter-1); i++) {
    wdata[i] = byte(i*7);
    if (i != 0) addrl[i] = addrl[i-1] + 1; // simulate address increment in PAGE mode
    SPIRAMDRVWDATA = wdata[i];
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    if (i == (num_iter-1)) {
      SPIRAMDRVCTL = 0x60; // 0x60 is write strobe, last=1
    } else {
      SPIRAMDRVCTL = 0x40; // 0x40 is write strobe, last=0
    }
  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");
    }
    Serial.println("=====");
  #endif

  // try slowing down the clock for the read (needed for >8MHz SPI clk)
  XLR8SPISRAM.page_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV4);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = 0x00;
  for (i=0; i <= (num_iter-1); i++) {
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    if (i == (num_iter-1)) {
      SPIRAMDRVCTL = 0xA0; // 0xA0 is write strobe, last=1
    } else {
      SPIRAMDRVCTL = 0x80; // 0x80 is write strobe, last=0
    }
    while (!(SPIRAMDRVCTL & _BV(VALID))) { // wait for data valid
    }
    rdata[i] = SPIRAMDRVRDATA;

  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"rdata:       0x%02X",rdata[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");

    }
  #endif // DEBUG

  error = false;
  for (i=0; i <= (num_iter-1); i++) {
    if (wdata[i] != rdata[i]) {
      error = true;
    }
  }
  if (error) {
    Serial.println("ERROR in PAGE mode");
  } else {
    Serial.println("PAGE mode PASSED");
  }
  Serial.println("--");
} // page_mode      

void seq_mode(uint16_t num_iter) {
  byte     wdata[num_iter];
  uint16_t addr[num_iter];
  byte     rdata[num_iter];
  sprintf(str,"Begin SEQ mode with %d iterations",num_iter);
  Serial.println(str);

  // seq mode, clk/2, no extended addr
  XLR8SPISRAM.sequential_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV2);

  addr[0] = 0x1000;
  SPIRAMDRVADDRH = addr[0] >> 8;
  SPIRAMDRVADDRL = addr[0] & 0xFF;

  for (i=0; i <= (num_iter-1); i++) {
    wdata[i] = byte(i*2);
    if (i != 0) addr[i] = addr[i-1] + 1; // simulate address increment in SEQ mode
    SPIRAMDRVWDATA = wdata[i];
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    if (i == (num_iter-1)) {
      SPIRAMDRVCTL = 0x60; // 0x60 is write strobe, last=1
    } else {
      SPIRAMDRVCTL = 0x40; // 0x40 is write strobe, last=0
    }
  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%04X",addr[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");
    }
    Serial.println("=====");
  #endif

  // try slowing down the clock for the read (needed for >8MHz SPI clk)
  XLR8SPISRAM.sequential_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV4);

  SPIRAMDRVADDRH = addr[0] >> 8;
  SPIRAMDRVADDRL = addr[0] & 0xFF;
  for (i=0; i <= (num_iter-1); i++) {
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    if (i == (num_iter-1)) {
      SPIRAMDRVCTL = 0xA0; // 0xA0 is write strobe, last=1
    } else {
      SPIRAMDRVCTL = 0x80; // 0x80 is write strobe, last=0
    }
    while (!(SPIRAMDRVCTL & _BV(VALID))) { // wait for data valid
    }
    rdata[i] = SPIRAMDRVRDATA;

  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%04X",addr[i]);
      Serial.println(str);
      sprintf(str,"rdata:       0x%02X",rdata[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");

    }
  #endif // DEBUG

  error = false;
  for (i=0; i <= (num_iter-1); i++) {
    if (wdata[i] != rdata[i]) {
      error = true;
    }
  }
  if (error) {
    Serial.println("ERROR in SEQ mode");
  } else {
    Serial.println("SEQ mode PASSED");
  }
  Serial.println("--");
} // seq_mode

void page_then_byte(uint16_t num_iter) {
  byte    wdata[num_iter];
  byte    addrl[num_iter];
  byte    rdata[num_iter];
  sprintf(str,"Begin PAGE_THEN_BYTE mode with %d iterations",num_iter);
  Serial.println(str);

  // page mode, clk/2, no extended addr
  XLR8SPISRAM.page_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV2);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = 0x00;
  addrl[0] = SPIRAMDRVADDRL;

  for (i=0; i <= (num_iter-1); i++) {
    wdata[i] = byte(i*7);
    if (i != 0) addrl[i] = addrl[i-1] + 1; // simulate address increment in PAGE mode
    SPIRAMDRVWDATA = wdata[i];
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    if (i == (num_iter-1)) {
      SPIRAMDRVCTL = 0x60; // 0x60 is write strobe, last=1
    } else {
      SPIRAMDRVCTL = 0x40; // 0x40 is write strobe, last=0
    }
  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");
    }
    Serial.println("=====");
  #endif

  // now switch to byte mode to do a few reads

  // byte mode, clk/4, no extended addr
  XLR8SPISRAM.byte_mode();
  XLR8SPISRAM.clock_divider(SPI_CLOCK_DIV4);

  SPIRAMDRVADDRH = 0x01;
  SPIRAMDRVADDRL = num_iter-1; // start at the end
  for (i=(num_iter-1); i >= 0; i--) {
    while (!(SPIRAMDRVCTL & _BV(RDY))) { // wait for req_rdy
    }
    SPIRAMDRVCTL = 0x80; // 0x80 is read strobe, last=0
    while (!(SPIRAMDRVCTL & _BV(VALID))) { // wait for data valid
    }
    rdata[i] = SPIRAMDRVRDATA;
    SPIRAMDRVADDRL --;

  }

  #ifdef DEBUG
    for (i=0; i <= (num_iter-1); i++) {
      sprintf(str,"address:     0x%02X%02X",SPIRAMDRVADDRH,addrl[i]);
      Serial.println(str);
      sprintf(str,"rdata:       0x%02X",rdata[i]);
      Serial.println(str);
      sprintf(str,"wdata:       0x%02X",wdata[i]);
      Serial.println(str);
      Serial.println("--");

    }
  #endif // DEBUG

  error = false;
  for (i=0; i <= (num_iter-1); i++) {
    if (wdata[i] != rdata[i]) {
      error = true;
    }
  }
  if (error) {
    Serial.println("ERROR in PAGE_THEN_BYTE mode");
  } else {
    Serial.println("PAGE_THEN_BYTE mode PASSED");
  }
  Serial.println("--");
} // page_then_byte mode

