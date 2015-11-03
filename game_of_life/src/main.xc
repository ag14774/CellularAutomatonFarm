// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include "bitArray.h"
#include "workerHelper.h"

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

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
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
void distributor(streaming chanend c_in, streaming chanend c_out, chanend fromAcc) {
  uchar val;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  uchar testArray[(IMHT*IMWD + 8 - 1) / 8];
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value
      changeBit(testArray, y, x, val, IMWD);
      c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
    }
  }
  printf( "\nOne processing round completed...\n" );
}

//TO BE MOVED TO HEADER FILE

uchar decide(int aliveNeighbours, uchar itselfAlive){
  if(aliveNeighbours<2)
    return 0;
  if(aliveNeighbours>3)
    return 0;
  if(aliveNeighbours==3)
    return 1;
  return itselfAlive;
}

uchar getBitWithGhosts(uchar A[], uchar ghostUp[], uchar ghostDown[],
                       int width, int height, int r, int c){
  if(c==-1)
    c = width-1;
  if(c==width)
    c = 0;
  if(r<0)
    return getBit(ghostUp, 0, c, width);
  if(r>=height)
    return getBit(ghostDown, 0, c, width);
  return getBit(A, r, c, width);
}

int countAliveNeighbours(uchar A[], uchar ghostUp[], uchar ghostDown[], int width, int height, int r, int c){
  int topLeftX = r - 1;
  int topLeftY = c - 1;
  int botRightX = r + 1;
  int botRightY = c + 1;
  int res = 0;
  uchar itself = getBit(A, r, c, width);
  for(int x = topLeftX ; x<=botRightX ; x++){
    for(int y = topLeftY ; y<=botRightY ; y++){
      res += getBitWithGhosts(A, ghostUp, ghostDown, width, height, r, c);
    }
  }
  return res - itself;
}

//-------------------------------

void worker(int id, streaming chanend distributor,
            const int ROWS, const int COLS, static const int DATAVOLUME){
  //DATAVOLUME = ((ROWS+2)*COLUMNS + 8 - 1) / 8
  uint8_t mode = FEEDING_MODE;
  uint8_t ghostsSent = 0;
  uint8_t ghostsReceived = 0;
  uchar A[DATAVOLUME];
  uchar B[DATAVOLUME];
  uchar *old = A;
  uchar *new = B;
  while(1){
    if(mode == FEEDING_MODE){
      select {
        case distributor :> uint8_t command: // signal beginning of data
          /*if(command == 0xFF){

            for(int r = 0; r<ROWS; r++){
              for(int c = 0; c<COLS; c++){
                up :> command;
                changeBit(data, r, c, command, COLS);
              }
            }

            while(1){
              up :> command;
              if(!isnull(down))
                down <: command;
              if(command == 0xFF)
                break;
            }

          }*/
          if(command!=DISTR_CODE){
            printf("ERROR OCCURED! WORKER %d DID NOT RECEIVE DISTRIBUTOR SIGNATURE(START OF MESSAGE)!\n",id);
            return;
          }
          //Reserve top and bottom row for ghosts
          for(int r=1 ; r<ROWS ; r++){
            receiveLineFrom(distributor, old, r, COLS);
          }

          distributor :> command;
          if(command!=0xFF){
            printf("ERROR OCCURED! WORKER %d DID NOT RECEIVE DISTRIBUTOR SIGNATURE(END OF MESSAGE)!\n",id);
            return;
          }
          mode = GHOST_EXCHANGE_MODE;
          break;
      }
    }
    else if (mode == GHOST_EXCHANGE_MODE) {
      timer tmr;
      select {
        case distributor :> uint8_t command: //REMEMBER TO SWAP CODES IN DISTRIBUTOR
          if(ghostsReceived == 2)
            mode = PROCESSING_MODE;
          if(command == WORKER_ABOVE){
            receiveLineFrom(distributor, old, 0, COLS);
            ghostsReceived++;
          } else if(command == WORKER_BELOW){
            receiveLineFrom(distributor, old, ROWS, COLS);
            ghostsReceived++;
          } else {
            printf("COMMAND INVALID IN THIS MODE!\n");
          }
          break;
        case !ghostsSent => tmr when timerafter(id*1000) :> void:
          sendLineTo(WORKER_ABOVE, distributor, old, 0, COLS);
          sendLineTo(WORKER_BELOW, distributor, old, ROWS, COLS);
          ghostsSent = 1;
          break;
      }
    }
    else if (mode == PROCESSING_MODE) {

    }
    else {

    }
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

  par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control);//thread to coordinate work on image
  }

  return 0;
}
