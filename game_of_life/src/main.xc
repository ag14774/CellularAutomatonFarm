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

#define NUMBEROFWORKERSINTILE0 5
#define NUMBEROFWORKERSINTILE1 7

#define MIN_CELLS_FOR_TILE1    64*64

#define MAXLINEBYTES 200//235
#define CHUNK0       790*MAXLINEBYTES//790
#define CHUNK1       1040*MAXLINEBYTES//1040

#define PERWORKERMEMORYINTILE1 CHUNK1/NUMBEROFWORKERSINTILE1

#define INPUT_FILE  "16x16.pgm"
#define OUTPUT_FILE "testout.pgm"

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

typedef interface d2w {
  [[clears_notification]]
  {int,int,int,uchar} get_data(uchar part[]); //returns startline to be used as base pointer
                                        //line count expected to be processed
                                        //total column count

  void send_line(uchar line[],int linenumber, int aliveCells);

  [[notification]]
  slave void data_ready(void);

} d2w;

typedef interface d2d {
  void get_data(uchar data[], int linesSent,
                int totalCols, int totalRows);

  int get_stats();

  void exchange_ghosts(uchar data[]);

  void set_workers_to(int numberOfWorkers);

  [[clears_notification]]
  void start_computation(uchar speedBoost);

  [[notification]]
  slave void step_completed(void);

  void get_line(uchar line[], int linenumber);

} d2d;

typedef interface ledControl {
  void send_command(int command);
} ledControl;

typedef interface buttonRequest {
  int requestUserInput(int requestedButton);
} buttonRequest;

typedef interface outInterface {
  [[guarded]]
  void request_line(uchar line[],int linenumber);

  [[guarded]]
  {int,int,uchar} initialize_transfer();

  [[notification]]
  slave void data_ready(void);

  [[clears_notification]]
  [[guarded]]
  void end_transfer();
} outInterface;

typedef interface inInterface {
  {int,int,uchar} initialize_transfer();

  [[notification]]
  slave void user_input_received(void);

  void request_line(uchar data[], int linenumber, int width, uchar rotate);

  [[clears_notification]]
  void end_transfer();
} inInterface;

typedef interface accInterface {
  [[guarded]]void pause();
  [[guarded]]void unpause();
} accInterface;

//DISPLAYS a LED pattern
[[distributable]]
void showLEDs(out port p, server ledControl clients[n], unsigned n) {
  int currentPattern = NO_LED;                      //1st bit...separate green LED
  while (1) {                                       //2nd bit...blue LED
    select{                                         //3rd bit...green LED
      case clients[int j].send_command(int command)://4th bit...red LED
        if(command==NO_LED)
          currentPattern = NO_LED;
        else if(command==SEP_GREEN_OFF)
          currentPattern &= ~SEP_GREEN_LED;
        else if(command==SEP_GREEN_ON)
          currentPattern |= SEP_GREEN_LED;
        else if(command==TOGGLE_SEP_GREEN)
          currentPattern ^= SEP_GREEN_LED;
        else if(command==BLUE_LED_OFF)
          currentPattern &= ~BLUE_LED;
        else if(command==BLUE_LED_ON)
          currentPattern |= BLUE_LED;
        else if(command==GREEN_LED_OFF)
          currentPattern &= ~GREEN_LED;
        else if(command==GREEN_LED_ON)
          currentPattern |= GREEN_LED;
        else if(command==RED_LED_OFF)
          currentPattern &= ~RED_LED;
        else if(command==RED_LED_ON)
          currentPattern |= RED_LED;
        p <: currentPattern;
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
[[distributable]]
void DataInStream(server inInterface fromDistributor, client ledControl toLeds, client buttonRequest fromButtons){
  char infname[] = INPUT_FILE;     //put your input image path here
  uchar rle=0;
  char *point;
  if((point = strrchr(infname,'.')) != NULL ) {
    if(strcmp(point,".rle") == 0) {
      rle = 1;
    }
  }
  int res;
  uchar line[MAXLINEBYTES];
  int storeForLater = 0;
  int count = 0;
  timer tmr;
  unsigned long duration;

  while(1){
    select{
      case fromDistributor.initialize_transfer() -> {int height, int width, uchar _rle}:
        fromButtons.requestUserInput(1);
        printf( "DataInStream: Start...\n" );
        //Open PGM file
        res = _openinpgm( infname );
        if( res ) {
          printf( "DataInStream: Error openening %s\n", infname );
          return;
        }
        height = _getheight();
        width  = _getwidth();
        _rle = rle;
        fromDistributor.user_input_received();
        toLeds.send_command(GREEN_LED_ON);
        tmr :> duration;
        break;
      case fromDistributor.request_line(uchar data[], int linenumber, int width, uchar rotate):
        //Read image byte-by-byte and copy line to distributor
        int pointer = 0;
        if(storeForLater>0)
          storeForLater--;
        if(rotate)
          _disable_buffering();
        for(int y=0;y<width;y++){
          uchar byte = 0;
          if(rotate)
            byte = _readinbyte_vert();
          else{
            if(storeForLater<=0) {
              byte = _readinbyte();
              if(rle && byte!='\n' && byte!='\r'){
                if(byte!='b' && byte!='o' && byte!='$' && byte!='!'){
                  count = count * 10 + (byte - '0');
                }
                if(byte=='b'){
                  if(count==0)
                    count = 1;
                  for(int l=0;l<count;l++){
                    changeBit(line, 0, pointer, 0, width);
                    pointer++;
                  }
                  count = 0;
                  if(pointer==width)
                    break;
                }
                if(byte=='o'){
                  if(count==0)
                    count = 1;
                  for(int l=0;l<count;l++){
                    changeBit(line, 0, pointer, 1, width);
                    pointer++;
                  }
                  count = 0;
                  if(pointer==width)
                    break;
                }
                if(byte=='$'){
                  storeForLater = count;
                  for(int l=0;l<(width-pointer);l++){
                    changeBit(line, 0, pointer+l, 0, width);
                  }
                  count = 0;
                  break;
                }
              }
            }
          }
          if(!rle || storeForLater>0)
            changeBit(line, 0, y, byte, width);
        }
        memcpy(data+lines2bytes(linenumber,width),line,lines2bytes(1,width));
        break;
      case fromDistributor.end_transfer():
        //Close PGM image file
        _closeinpgm();
        toLeds.send_command(GREEN_LED_OFF);
        unsigned long temp;
        tmr :> temp;
        duration = temp - duration;
        printf("Duration: %f",duration/100000.0f);
        break;
  }
 }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(client inInterface toDataIn, server outInterface i_out, server accInterface fromAcc,
                 client ledControl toLeds, server d2w workers[n], unsigned n, client d2d slaveDist) {
  uchar data[CHUNK0];
  uchar nextTopGhost[MAXLINEBYTES];
  uchar lineBuffer[MAXLINEBYTES];
  int height;
  int width;
  int mode = STEP_COMPLETED_MODE;
  int nextLineToBeAllocated;
  int linesUpdated = 0;
  long aliveCellsThisStep = 0;
  long round = 0;
  uchar outputRequested = 0;
  uchar pauseRequested = 0;

  timer tmr;
  float duration = 0;
  long time;

  unsigned int last100RoundsDuration = 0;
  uchar consecutiveRounds = 0;
  unsigned int lastPolledTime = 0;

  uchar workersInTile0 = 4;
  uchar workersInTile0_best = 4;
  uchar workersInTile1 = 1;
  uchar workersInTile1_best = 1;
  uchar maxWorkersTile0 = NUMBEROFWORKERSINTILE0;
  uchar maxWorkersTile1 = NUMBEROFWORKERSINTILE1;
  float maxSpeedAchieved = 99999;
  int roundsProcessedWithThisSetup = -1;
  float lastDuration = 0;
  uchar bestFound = 1;

  uchar rotate = 0;

  //It's always beneficial to use both Tiles
  uchar useTile1 = 1;
  uchar availableWorkers = n;
  int linesForD2 = 0;
  int linesForD1 = 0;

  printf("Press button 1 to start.\n");

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  uchar rle = 0;
  {height,width,rle} = toDataIn.initialize_transfer();
  printf("Image size = %dx%d\n", height, width );
  if(!rle && ( (height<12 && width>height) || lines2bytes(1,width)>=MAXLINEBYTES ) ){
    rotate = 1;
    printf("**************WARNING**************\n");
    printf("The system has detected that the image provided has to be\n");
    printf("rotated before processing can begin.\n");
    printf("All I/O operations may be significantly slower!!!\n");
    printf("***********************************\n");
    unsigned int temp = height;
    height = width;
    width = temp;
  }

  int testRounds = keepWithinBounds(3000000/(width * height),5,1000);
  if((height*width)>=MIN_CELLS_FOR_TILE1 || useTile1){
    useTile1 = 1;
  }
  useTile1 = 0;

  if(useTile1){
    maxWorkersTile0 = keepWithinBounds(height/2,1,NUMBEROFWORKERSINTILE0);
    maxWorkersTile1 = keepWithinBounds(height - maxWorkersTile0,1,NUMBEROFWORKERSINTILE1);
    workersInTile1 = 7;
    workersInTile1_best = 7;
  }
  else {
    maxWorkersTile0 = keepWithinBounds(height,1,NUMBEROFWORKERSINTILE0);
    maxWorkersTile1 = 0;
  }
  slaveDist.set_workers_to(workersInTile1);
  availableWorkers = maxWorkersTile0 + maxWorkersTile1;

  float ratio = ((float)maxWorkersTile1)/availableWorkers;
  if(ratio==0){
    useTile1 = 0;
    printf("test\n");
  }
  do{
    if(useTile1)
      linesForD2 = (int) (ratio*height);
    linesForD1 = height - linesForD2;
    ratio = ratio - 0.01;
  } while (lines2bytes(linesForD2,width)>CHUNK1 && ratio>((float)CHUNK1)/(CHUNK0+CHUNK1));
  printf("%d\n",linesForD1);
  printf("%d\n",linesForD2);
  select{
    case toDataIn.user_input_received():
      for( int y = 1; y <= height; y++ ) {
          int j;
          if(y<=linesForD2)
            j = y;
          else
            j = y - linesForD2;
          toDataIn.request_line(data, j, width, rotate);
          //STARTLINE FOR TILE 0 = linesForD2
          if(y==linesForD2)
            slaveDist.get_data(data, linesForD2, width, height);
      }
      toDataIn.end_transfer();
      break;
  }

  if(useTile1) {
    slaveDist.exchange_ghosts(data);
  }
  else {
    memcpy(data,data+lines2bytes(linesForD1,width),lines2bytes(1,width));
    memcpy(data+lines2bytes(linesForD1+1,width),data+lines2bytes(1,width),lines2bytes(1,width));
  }

  printf("Processing...\n");
  printf("Adjusting number of workers for highest possible speed...\n");
  printf("Pausing and Output requests are temporarily disabled...\n");

  tmr :> time;
  while(1) {
    if(mode == STEP_COMPLETED_MODE){
      toLeds.send_command(TOGGLE_SEP_GREEN);
      if(consecutiveRounds == 0)
        tmr :> lastPolledTime;
      if(consecutiveRounds == 100){
        last100RoundsDuration = lastPolledTime;
        tmr :> lastPolledTime;
        last100RoundsDuration = lastPolledTime - last100RoundsDuration;
        consecutiveRounds = -1;
      }
      if(outputRequested){
        consecutiveRounds = -1;
        i_out.data_ready();
        while(outputRequested){
          select{
            case i_out.request_line(uchar line[], int linenumber):
                if(linenumber<linesForD2){
                  slaveDist.get_line(lineBuffer,linenumber);
                  memcpy(line, lineBuffer, lines2bytes(1,width));
                }
                else{
                  memcpy(line,data+lines2bytes(linenumber-linesForD2+1,width),lines2bytes(1,width));
                }
                break;
            case i_out.end_transfer():
                tmr :> time;
                outputRequested = 0;
                break;
          }
        }
      }
      if (pauseRequested){
        toLeds.send_command(RED_LED_ON);
        consecutiveRounds = -1;
        if(useTile1)
          aliveCellsThisStep = aliveCellsThisStep + slaveDist.get_stats();
        printReport(round,duration,aliveCellsThisStep, width*height, last100RoundsDuration);
        select {
          case fromAcc.unpause():
            pauseRequested = 0;
            tmr :> time;
            toLeds.send_command(RED_LED_OFF);
            break;
        }
      }

      nextLineToBeAllocated = 1;
      memcpy(nextTopGhost, data, lines2bytes(1,width));
      linesUpdated = 0;
      aliveCellsThisStep = 0;
      round++;
      if(useTile1)
        slaveDist.start_computation(bestFound);
      for(int i = 0;i<workersInTile0;i++){
        workers[i].data_ready();
      }

      consecutiveRounds++;
      roundsProcessedWithThisSetup++;
      if(roundsProcessedWithThisSetup==testRounds && !bestFound){
        float durationWithThisSetup = (duration-lastDuration);
        if(durationWithThisSetup <= maxSpeedAchieved){
          maxSpeedAchieved = durationWithThisSetup;
          workersInTile0_best = workersInTile0;
          workersInTile1_best = workersInTile1;
        }
        lastDuration = duration;
        roundsProcessedWithThisSetup = 0;
        if((workersInTile0+workersInTile1) == availableWorkers){
          bestFound = 1;
          workersInTile0 = workersInTile0_best;
          workersInTile1 = workersInTile1_best;
          slaveDist.set_workers_to(workersInTile1);
          printf("Most efficient number of workers found for tile 0: %d!\n",workersInTile0);
          printf("Most efficient number of workers found for tile 1: %d!\n",workersInTile1);
          printf("Pausing and Output requests are now enabled...\n");
          fflush(stdout);
        }else{
          if(workersInTile1>maxWorkersTile0 && workersInTile1!=maxWorkersTile1){
            workersInTile1++;
            slaveDist.set_workers_to(workersInTile1);
          }
          if(workersInTile1==workersInTile0 && workersInTile1!=maxWorkersTile1){
            workersInTile1++;
            slaveDist.set_workers_to(workersInTile1);
          }
          if(!useTile1||(workersInTile0<workersInTile1 && workersInTile0!=maxWorkersTile0))
            workersInTile0++;
        }
        tmr :> time;
      }
      mode = NEW_STEP_MODE;
    }
    [[ordered]]
    select {
      case tmr when timerafter(time) :> void:
          time += 50000000;
          duration += 0.5;
          break;
      case bestFound => i_out.initialize_transfer() -> {int outheight, int outwidth, uchar rotateEnable}:
          outheight = height;
          outwidth = width;
          rotateEnable = rotate;
          outputRequested = 1;
          break;
      case bestFound => fromAcc.pause():
          pauseRequested = 1;
          printf("pause requested\n");
          break;
      case workers[int j].get_data(uchar part[])
           -> {int start_line, int lines_sent, int totalCols, uchar speedBoost}:
           start_line = nextLineToBeAllocated;
           lines_sent = 1;
           nextLineToBeAllocated = start_line + lines_sent;
           totalCols = width;
           memcpy(part, nextTopGhost, lines2bytes(1,width));
           memcpy(part + lines2bytes(1,width), data+lines2bytes(start_line,width),lines2bytes(lines_sent+1,width));
           memcpy(nextTopGhost, data+lines2bytes(nextLineToBeAllocated-1,width),lines2bytes(1,width)); //update nextTopGhost
           speedBoost = bestFound;
           break;
      case workers[int j].send_line(uchar line[], int linenumber, int aliveCells):
          memcpy(data+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesUpdated++;
          aliveCellsThisStep += aliveCells;
          if(linesUpdated==linesForD1){
            if(useTile1) {
              select{
                case slaveDist.step_completed():
                  slaveDist.exchange_ghosts(data);
                  break;
              }
            }
            else {
              memcpy(data,data+lines2bytes(linesForD1,width),lines2bytes(1,width));
              memcpy(data+lines2bytes(linesForD1+1,width),data+lines2bytes(1,width),lines2bytes(1,width));
            }
            mode = STEP_COMPLETED_MODE;
          }
          else if(nextLineToBeAllocated <= linesForD1){
            workers[j].data_ready();
          }
          break;
    }
  }
}

void distributor_tile_one(server d2d masterDist, server d2w workers[n], unsigned n) {
  uchar half[CHUNK1];
  uchar nextTopGhost[MAXLINEBYTES];
  int linesReceived, height, width;

  int nextLineToBeAllocated;
  int linesUpdated = 0;
  long aliveCellsThisStep = 0;
  uchar speedBoost = 0;

  uchar currentWorkers = 0;

  while(1) {
    select {
      case masterDist.set_workers_to(int numberOfWorkers):
          currentWorkers = numberOfWorkers;
          break;
      case masterDist.get_data(uchar data[], int lines_sent, int totalCols, int totalRows):
          linesReceived = lines_sent;
          width = totalCols;
          height = totalRows;
          memcpy(half+lines2bytes(1,width), data+lines2bytes(1,width), lines2bytes(linesReceived,width));
          masterDist.step_completed();
          break;
      case masterDist.exchange_ghosts(uchar data[]):
          memcpy(half, data+lines2bytes(height-linesReceived,width), lines2bytes(1,width));
          memcpy(half+lines2bytes(linesReceived+1,width), data+lines2bytes(1, width), lines2bytes(1,width));
          memcpy(data, half+lines2bytes(linesReceived,width), lines2bytes(1,width));
          memcpy(data+lines2bytes(height-linesReceived+1,width), half+lines2bytes(1,width), lines2bytes(1,width));
          break;
      case masterDist.start_computation(uchar sb):
          speedBoost = sb;
          //********************** NOTIFY WORKERS AND INITIALIZE ***************************
          for(int i = 0; i<currentWorkers ;i++){
            workers[i].data_ready();
          }
          nextLineToBeAllocated = 1;
          memcpy(nextTopGhost, half, lines2bytes(1,width));
          linesUpdated = 0;
          aliveCellsThisStep = 0;
          break;
      case masterDist.get_line(uchar line[], int linenumber):
          memcpy(line, half+lines2bytes(linenumber+1,width), lines2bytes(1,width));
          break;
      case masterDist.get_stats() -> {int aliveCells}:
          aliveCells = aliveCellsThisStep;
          break;
      case workers[int j].get_data(uchar part[])
          -> {int start_line, int lines_sent, int totalCols, uchar sb}:
          sb = speedBoost;
          start_line = nextLineToBeAllocated;
          lines_sent = 1;
          nextLineToBeAllocated = start_line + lines_sent;
          totalCols = width;
          memcpy(part, nextTopGhost, lines2bytes(1,width));
          memcpy(part + lines2bytes(1,width), half+lines2bytes(start_line,width),lines2bytes(lines_sent+1,width));
          memcpy(nextTopGhost, half+lines2bytes(nextLineToBeAllocated-1,width),lines2bytes(1,width)); //update nextTopGhost
          break;
      case workers[int j].send_line(uchar line[], int linenumber, int aliveCells):
          memcpy(half+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesUpdated++;
          aliveCellsThisStep += aliveCells;
          if(linesUpdated==linesReceived)
            masterDist.step_completed();
          else if(nextLineToBeAllocated<=linesReceived)
            workers[j].data_ready();
          break;
    }
  }
}

void worker(int id, client d2w distributor){
  uchar part[MAXLINEBYTES*3];
  uchar line[MAXLINEBYTES];
  int startLine = 0;
  int linesReceived = 0;
  int totalCols = 0;
  uchar speedBoost = 0;
  while(1){
    select {
      case distributor.data_ready():
        {startLine,linesReceived,totalCols,speedBoost} = distributor.get_data(part);
        break;
    }

    //PROCESS HERE AND COMMUNICATE EACH LINE
    for(int x=1; x<=linesReceived;x++){
      int aliveCells = 0;
      if(speedBoost){
        clearBit(line,0,0,totalCols);
        clearBit(line,0,totalCols-1,totalCols);
        uchar markedNext = 0;
        for(int y=0; y<totalCols;y++){
          uchar count = getBit(part, x, y, totalCols);
          count += getBit(part, x-1, y, totalCols);
          count += getBit(part, x+1, y, totalCols);
          if(count == 0 && y!=totalCols-1 && !markedNext)
            clearBit(line,0,y,totalCols);
          markedNext = 0;
          if(count>0)
            setBit(line, 0, y, totalCols);
          if(count>1){
            setBit(line, 0, mod(y-1,totalCols), totalCols);
            setBit(line, 0, mod(y+1,totalCols), totalCols);
            markedNext = 1;
          }
        }
      }
      for(int y=0; y<totalCols;y++){
        if(getBit(line,0,y,totalCols) || !speedBoost){
          uchar itself = getBit(part, x, y, totalCols);
          int neighbours = countAliveNeighbours(part, x, y, totalCols);
          uchar res = decide(neighbours, itself);
          aliveCells += (res?1:0);
          changeBit(line, 0, y, res, totalCols);
        }
      }
      distributor.send_line(line,startLine+x-1,aliveCells);
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
  int height, width;
  uchar rotate = 0;
  uchar line[MAXLINEBYTES];

  //Open PGM file

  delay_milliseconds(200);

  while(1){
    int pressed = toButtons.requestUserInput(2);
    {height,width,rotate} = fromDistributor.initialize_transfer();
    printf( "DataOutStream:Start...\n" );
    select {
      case fromDistributor.data_ready():
        toLeds.send_command(BLUE_LED_ON);
        if(rotate)
          res = _openoutpgm( outfname, height, width );
        else
          res = _openoutpgm( outfname, width, height );
        if( res ) {
          printf( "DataOutStream:Error opening %s\n.", outfname );
        }else {
          //Compile each line of the image and write the image line-by-line
          for( int y = 0; y < height; y++ ) {
            fromDistributor.request_line(line, y);
            for(int x = 0;x < width;x++) {
              uchar c =(uchar) (getBit(line,0,x,width)*255);
              if(rotate)
                _writeoutbyte_vert(c);
              else
                _writeoutbyte(c);
            }
          }
          _closeoutpgm();
          fromDistributor.end_transfer();
          toLeds.send_command(BLUE_LED_OFF);
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
void accelerometer(client interface i2c_master_if i2c, client accInterface toDist) {
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

    if (!tilted) {
      if (x>70) {
        tilted = 1;
        toDist.pause();
      }
    }else {
      if (x<5) {
        tilted = 0;
        toDist.unpause();
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

  d2w i_d2w[NUMBEROFWORKERSINTILE0];
  d2w i_d2w_tile_one[NUMBEROFWORKERSINTILE1];
  d2d master2slave;
  ledControl i_ledControl[3];
  buttonRequest i_buttonRequests[2];
  outInterface i_out;
  inInterface i_in;
  accInterface i_acc;

  par {
    on tile[0]:buttonListener(buttons,i_buttonRequests,2);
    on tile[0]:i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0]:accelerometer(i2c[0],i_acc);        //client thread reading accelerometer data
    on tile[0]:showLEDs(leds,i_ledControl,3);
    on tile[0]:DataInStream(i_in, i_ledControl[0], i_buttonRequests[0]);          //thread to read in a PGM image
    on tile[0]:DataOutStream(i_out, i_ledControl[1], i_buttonRequests[1]);       //thread to write out a PGM image
    on tile[0]:distributor(i_in, i_out, i_acc, i_ledControl[2], i_d2w, NUMBEROFWORKERSINTILE0, master2slave);//thread to coordinate work on image
    par(int i=0 ; i<NUMBEROFWORKERSINTILE0 ; i++){
      on tile[0]:worker(i, i_d2w[i]);
    }

    on tile[1]:distributor_tile_one(master2slave, i_d2w_tile_one, NUMBEROFWORKERSINTILE1);
    par(int i=0 ; i<NUMBEROFWORKERSINTILE1 ; i++){
      on tile[1]:worker(i+NUMBEROFWORKERSINTILE0, i_d2w_tile_one[i]);
    }

  }

  return 0;
}
