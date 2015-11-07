// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <string.h>
#include "pgmIO.h"
#include "i2c.h"
#include "workerHelper.h"

#define NUMBEROFWORKERSINTILE0 3
#define NUMBEROFWORKERSINTILE1 7

#define MAXLINEBYTES 250
#define CHUNK0       95*1024

#define PERWORKERMEMORYINTILE0 CHUNK0/NUMBEROFWORKERSINTILE0
#define PERWORKERMEMORYINTILE1 CHUNK0/NUMBEROFWORKERSINTILE1

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
port p_sda = XS1_PORT_1F;

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

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

typedef interface d2w{
  [[clears_notification]]
  {int,int,int,int} get_data(uchar part[]); //returns startline to be used as base pointer
                                        //line count expected to be processed
                                        //total column count

  void get_ghosts(uchar part[], int ghost_Up, int ghost_Down, int ghost_Down_Destination);

  void send_line(uchar line[],int linenumber);

  [[notification]]
  slave void data_ready(void);


} d2w;

//DISPLAYS a LED pattern
int showLEDs(out port p, chanend fromVisualiser) {
  int shutdown = 0;
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (!shutdown) {
    fromVisualiser :> pattern;   //receive new pattern from visualiser
    if(pattern == 0xFF)
      shutdown = 1;
    else
      p <: pattern;                //send pattern to LED port
  }
  printf("Led Controller is shutting down\n");
  return 0;
}

//READ BUTTONS and send button pattern to userAnt
void buttonListener(in port b, chanend toUserAnt) {
  int shutdown = 0;
  int r;
  while (!shutdown) {
    b when pinseq(15)  :> r;
    select {
      case b when pinsneq(15) :> r:
        //b when pinseq(15)  :> r;    // check that no button is pressed
        //b when pinsneq(15) :> r;    // check if some buttons are pressed
        if ((r==13) || (r==14))     // if either button is pressed
        toUserAnt <: r;             // send button pattern to userAnt
        break;
      case toUserAnt :> shutdown:
        shutdown = 1;
        break;
    }
  }
  printf("Button listener shutting down\n");
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], streaming chanend c_out){
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
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
    //printf( "\n" );
  }

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
void distributor(streaming chanend c_in, streaming chanend c_out, chanend fromAcc, server d2w workers[n], unsigned n) {
  uchar val;
  uchar data[CHUNK0];
  int height;
  int width;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  c_in :> height;
  c_in :> width;
  for( int y = 0; y < height; y++ ) {   //go through all lines
    for( int x = 0; x < width; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      changeBit(data, y, x, val, width);
//      c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
    }
  }

  int linesPerWorker = height / NUMBEROFWORKERSINTILE0;
  int extraLines     = height % NUMBEROFWORKERSINTILE0;
  int nextLineToBeAllocated = 0;

  for(int i = 0;i<n;i++){
    workers[i].data_ready();
  }
  int linesReceived = 0;
  while(1) {
    select {
      case workers[int j].get_data(uchar part[])
          -> {int startLine, int linesSent, int totalCols, int totalRows}:
          startLine = nextLineToBeAllocated;
          linesSent = linesPerWorker + (extraLines?1:0);
          extraLines--;
          nextLineToBeAllocated = startLine + linesSent;
          totalCols = width;
          totalRows = height;
          memcpy(part+lines2bytes(1,width),data+lines2bytes(startLine,width),lines2bytes(linesSent,width));
          break;
      case workers[int j].get_ghosts(uchar part[], int ghost_Up, int ghost_Down, int ghost_Down_Dest):
          memcpy(part,data+lines2bytes(ghost_Up,width),lines2bytes(1,width));
          memcpy(part+lines2bytes(ghost_Down_Dest,width),data+lines2bytes(ghost_Down,width),lines2bytes(1,width));
          break;
      case workers[int j].send_line(uchar line[], int linenumber):
          memcpy(data+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesReceived++;
          if(linesReceived==16){
            for( int y = 0; y < height; y++ ) {   //go through all lines
                for( int x = 0; x < width; x++ ) { //go through each pixel per line
                  uchar ch = getBit(data, y, x, width);
                  c_out <: (uchar) (ch*255);
                  //printf("%d ",ch);    //read the pixel value
                }
                //printf("\n");
              }
          }
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
  select {
    case distributor.data_ready():
      {startLine,linesReceived,totalCols,totalRows} = distributor.get_data(part);
      break;
  }
//  printf("Worker %d: %d %d %d %d\n",id,startLine,linesReceived,totalCols,totalRows);

  distributor.get_ghosts(part, mod(startLine-1,totalRows),
                         mod(startLine+linesReceived,totalRows), linesReceived+1);

  //PROCESS HERE AND COMMUNICATE EACH LINE
  for(int x=1; x<=linesReceived;x++){
    for(int y=0; y<totalCols;y++){
      uchar itself = getBit(part, x, y, totalCols);
      int neighbours = countAliveNeighbours(part, x, y, totalCols);
      uchar res = decide(neighbours, itself);
      changeBit(line, 0, y, res, totalCols);
//      printf("%d ",res);
    }
//    printf("\n");
    distributor.send_line(line,startLine+x-1);
  }

}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], streaming chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream:Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream:Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];
    }
    _writeoutline( line, IMWD );
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
  return;
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

  char infname[] = "test.pgm";     //put your input image path here
  char outfname[] = "testout.pgm"; //put your output image path here
  chan c_control;
  streaming chan c_inIO, c_outIO;       //extend your channel definitions here
  d2w i_d2w[3];

  par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control, i_d2w, 3);//thread to coordinate work on image
    worker(0, i_d2w[0]);
    worker(1, i_d2w[1]);
    worker(2, i_d2w[2]);
  }

  return 0;
}
