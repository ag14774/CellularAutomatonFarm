// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <string.h>
#include "i2c.h"
#include "pgmIO.h"
#include "helper.h"

on tile[0] : port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
on tile[0] : port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for accelerometer
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

#define NUMBEROFWORKERSINTILE0 3
#define NUMBEROFWORKERSINTILE1 7

#define MAXLINEBYTES 250
#define CHUNK0       95*1024

#define PERWORKERMEMORYINTILE0 CHUNK0/NUMBEROFWORKERSINTILE0
#define PERWORKERMEMORYINTILE1 CHUNK0/NUMBEROFWORKERSINTILE1

#define  IMHT 64                  //image height
#define  IMWD 64                  //image width

#define INPUT_FILE "test.pgm"
#define OUTPUT_FILE "testout.pgm"

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

typedef interface d2w {
  [[clears_notification]]
  {int,int,int,int} get_data(uchar part[]); //returns startline to be used as base pointer
                                        //line count expected to be processed
                                        //total column count
//  void get_ghosts(uchar part[], int ghost_Up, int ghost_Down, int ghost_Down_Destination);

  void send_line(uchar line[],int linenumber);

  [[notification]]
  slave void data_ready(void);

} d2w;

typedef interface ledControl {
  void send_pattern(int pattern);
} ledControl;

typedef interface buttonRequest {
  int requestUserInput(int requestedButton);
} buttonRequest;

typedef interface outInterface {
  [[guarded]]
  void request_line(uchar line[],int linenumber);

  [[guarded]]
  void initialize_transaction();

  [[notification]]
  slave void data_ready(void);

  [[clears_notification]]
  [[guarded]]
  void end_transaction();
} outInterface;

//DISPLAYS a LED pattern
[[distributable]]
void showLEDs(out port p, server ledControl clients[n], unsigned n) {
               //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    select{
      case clients[int j].send_pattern(int pattern):
        p <: pattern;                //send pattern to LED port
        break;
    }
  }
}



//READ BUTTONS and send button pattern to userAnt
[[distributable]]
void buttonListener(in port b, server buttonRequest clients[n], unsigned n) {
  int r;
  while (1) {
    select{
      case clients[int j].requestUserInput(int buttonRequested) -> int correctButtonPressed:
          if(buttonRequested==1)
            buttonRequested=14;
          else
            buttonRequested=13;
          correctButtonPressed = 0;
          do{
            b when pinseq(15)  :> r;    // check that no button is pressed
            b when pinsneq(15) :> r;    // check if some buttons are pressed
            if(r==buttonRequested)
              correctButtonPressed = 1;
          } while (!correctButtonPressed);
          break;
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(streaming chanend c_out, client ledControl toLeds){
  char infname[] = INPUT_FILE;     //put your input image path here
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  c_out <: IMHT;
  c_out <: IMWD;
  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      toLeds.send_pattern(4);
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
  }
  toLeds.send_pattern(0);

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream:Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(streaming chanend c_in, server outInterface i_out, chanend fromAcc, server d2w workers[n], unsigned n) {
  uchar data[CHUNK0];
  int height;
  int width;
  int linesReceived = -1;
  int linesPerWorker;
  int extraLines;
  int nextLineToBeAllocated;
  uint8_t outputRequested = 0;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
//  fromAcc :> int value;
  printf( "Processing...\n" );

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  uchar val;
  c_in :> height;
  c_in :> width;
  for( int y = 0; y < height; y++ ) {   //go through all lines
    for( int x = 0; x < width; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      changeBit(data, y, x, val, width);
    }
  }

  while(1) {
    if(linesReceived == -1){
      if(outputRequested)
        i_out.data_ready();
      while(outputRequested){
        select{
          case i_out.request_line(uchar line[], int linenumber):
              memcpy(line,data+lines2bytes(linenumber,width),lines2bytes(1,width));
              break;
          case i_out.end_transaction():
            outputRequested = 0;
            break;
        }
      }
      linesPerWorker = height / NUMBEROFWORKERSINTILE0;
      extraLines     = height % NUMBEROFWORKERSINTILE0;
      nextLineToBeAllocated = 0;
      for(int i = 0;i<n;i++){
        workers[i].data_ready();
      }
    }
    select {
      case workers[int j].get_data(uchar part[])
          -> {int startLine, int linesSent, int totalCols, int totalRows}:
          linesReceived=0;
          startLine = nextLineToBeAllocated;
          linesSent = linesPerWorker + (extraLines>0?1:0);
          extraLines--;
          nextLineToBeAllocated = startLine + linesSent;
          totalCols = width;
          totalRows = height;
          //refactor this part
          memcpy(part+lines2bytes(1,width),data+lines2bytes(startLine,width),lines2bytes(linesSent,width));
          memcpy(part,data+lines2bytes(mod(startLine-1,totalRows),width),lines2bytes(1,width));
          memcpy(part+lines2bytes(linesSent+1,width),data+lines2bytes(mod(startLine+linesSent,totalRows),width),lines2bytes(1,width));
          break;
      case workers[int j].send_line(uchar line[], int linenumber):
          memcpy(data+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesReceived++;
          if(linesReceived==height)
            linesReceived = -1;
          break;
      case i_out.initialize_transaction():
        outputRequested = 1;
        break;
    }
  }

  printf( "\nOne processing round completed...\n" );
}

void worker(int id, client d2w distributor){
  uchar part[PERWORKERMEMORYINTILE0];
  uchar line[MAXLINEBYTES];
  int startLine = 0;
  int linesReceived = 0;
  int totalCols = 0;
  int totalRows = 0;
  while(1){
    select {
      case distributor.data_ready():
        {startLine,linesReceived,totalCols,totalRows} = distributor.get_data(part);
        break;
    }

    //PROCESS HERE AND COMMUNICATE EACH LINE
    for(int x=1; x<=linesReceived;x++){
      for(int y=0; y<totalCols;y++){
        uchar itself = getBit(part, x, y, totalCols);
        int neighbours = countAliveNeighbours(part, x, y, totalCols);
        uchar res = decide(neighbours, itself);
        changeBit(line, 0, y, res, totalCols);
      }
      distributor.send_line(line,startLine+x-1);
    }
  }

}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(client outInterface fromDistributor, client ledControl toLeds, client buttonRequest toButtons)
{
  char outfname[] = OUTPUT_FILE; //put your output image path here
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream:Start...\n" );


  while(1){
    int pressed = toButtons.requestUserInput(1);
    fromDistributor.initialize_transaction();
    select {
      case fromDistributor.data_ready():
        toLeds.send_pattern(2);
        res = _openoutpgm( outfname, IMWD, IMHT );
        if( res ) {
          printf( "DataOutStream:Error opening %s\n.", outfname );
        }else {
          //Compile each line of the image and write the image line-by-line
          for( int y = 0; y < IMHT; y++ ) {
            fromDistributor.request_line(line, y);
            for(int x = 0;x < IMWD;x++) {
              uchar c =(uchar) (getBit(line,0,x,IMWD)*255);
              _writeoutbyte(c);
            }
          }
          _closeoutpgm();
          fromDistributor.end_transaction();
          toLeds.send_pattern(0);
        }
        break;
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read accelerometer, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the accelerometer x-axis forever
  while (1) {

    //check until new accelerometer data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer

  chan c_control;
  streaming chan c_inIO;       //extend your channel definitions here
  d2w i_d2w[NUMBEROFWORKERSINTILE0];
  ledControl i_ledControl[2];
  buttonRequest i_buttonRequests[1];
  outInterface i_out;

  par {
    on tile[0]:buttonListener(buttons,i_buttonRequests,1);
    on tile[0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0]:accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    on tile[0]:showLEDs(leds,i_ledControl,2);
    on tile[0]:DataInStream(c_inIO, i_ledControl[0]);          //thread to read in a PGM image
    on tile[0]:DataOutStream(i_out, i_ledControl[1], i_buttonRequests[0]);       //thread to write out a PGM image
    on tile[0]:distributor(c_inIO, i_out, c_control, i_d2w, NUMBEROFWORKERSINTILE0);//thread to coordinate work on image
    par(int i=0 ; i<NUMBEROFWORKERSINTILE0 ; i++){
      on tile[0]:worker(i, i_d2w[i]);
    }

  }

  return 0;
}
