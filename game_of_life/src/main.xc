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

#define MAXLINEBYTES  233//MAXIMUM SPACE ALLOCATED FOR A LINE
#define TILE0LINESMAX 790//MAXLINES FOR TILE0
#define TILE1LINESMAX 1040//MAXLINES FOR TILE1
#define CHUNK0        TILE0LINESMAX*MAXLINEBYTES//790
#define CHUNK1        TILE1LINESMAX*MAXLINEBYTES//1040

//SET INPUT FILE HERE
#define INPUT_FILE  "64x64.pgm"
#define OUTPUT_FILE "testout.pgm"

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

typedef interface d2w {
  /**
   * Function that the worker uses to get data from distributor.
   * This will also clear the notification raised by the distributor
   * @param part Reference to worker's array
   * @return   Start line in the image
   *           How many lines have I received
   *           Width of the image
   *           Should I compute all cells or detect which cells require computation(dynamic computation)
   */
  [[clears_notification]]
  {int,int,int,uchar} get_data(uchar part[]);

  /**
   * Function that the worker uses to send a line to the distributor
   * @param line Reference to the array that holds the processed line
   * @param linenumber Which line in the image is that?
   * @param How many alive cells on this line
   *
   */
  void send_line(uchar line[], int linenumber, int aliveCells);

  /**
   * Notification function. This is used by the distributor to raise
   * a notification to the worker that there is data ready
   */
  [[notification]]
  slave void data_ready(void);

} d2w;

typedef interface d2d {
  /**
   * Function used by the master distributor to give the data to
   * the slave distributor
   * @param data Reference to the array that holds the data
   * @param linesSent How many lines are being sent
   * @param totalCols Total width
   * @param totalRows Total height
   */
  void get_data(uchar data[], int linesSent,
                int totalCols, int totalRows);

  /**
   * @return How many alive cells are there in the image
   *         stored in tile 1?
   */
  int get_stats(); //get alive cells from tile 1

  /**
   * After half of the image is sent, the distributor uses this
   * to exchange ghost rows.
   * @param data Reference to the array of master distributor
   */
  void exchange_ghosts(uchar data[]);

  /**
   * Used by the master distributor to command the slave distributor,
   * how many workers to use
   */
  void set_workers_to(int numberOfWorkers); //use this number of workers

  [[clears_notification]]
  void start_computation(uchar speedBoost); //start next round

  [[notification]]
  slave void step_completed(void); //raise notification to tile 0 that I'm done

  void get_line(uchar line[], int linenumber); //get specified line. Used for output.

} d2d;

typedef interface ledControl {
  void send_command(int command); //available commands defined in helper.h
} ledControl;

typedef interface buttonRequest {
  int requestUserInput(int requestedButton); //wait until the specified button is pressed
} buttonRequest;

typedef interface outInterface {
  /**
   * Request line from the distributor
   * @param line Where to put the line
   * @param linenumber Which line do you want
   */
  [[guarded]]
  void request_line(uchar line[],int linenumber);

  /**
   * Request an output
   * @return Width
   *         Height
   *         Should I rotate the image?
   */
  [[guarded]]
  {int,int,uchar} initialize_transfer();

  [[notification]]
  slave void data_ready(void);  //notify the Data out that the data is ready

  [[clears_notification]]
  [[guarded]]
  void end_transfer();  //terminate transfer after all lines are printed
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

/**
 * DISPLAYS a LED pattern.
 * Does not use a core. The core that sends the command should also execute
 * the task.  Commands are defined in helper.h
 */
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



/**
 * When someone requests for a button press, stay in the loop until he presses
 * the correct button. This is possible because once the image is read, we are
 * required to listen for only one button press(output request button). In the start of
 * the system, we only want to listen for input requests. To achieve that we add an initial delay
 * to the Data out stream so that Data In stream has time to call the buttonListener first.
 * The buttonListener is controlled by the Data In until an input is requested. After that, the
 * Data out exclusively controls  the button listener.
 */
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
// Read Image from PGM file from path infname[]. When the distributor asks for the image
// the Data In will wait for user input. The whole procedure is executed by the same core.
// Once user input is received, the header containing the dimensions of the image is read
// and sent back to the distributor. This raises a notification that is only cleared after
// the distributor call the end_transfer() function.
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
        break;
      case fromDistributor.request_line(uchar data[], int linenumber, int width, uchar rotate):
        //Read image byte-by-byte and copy line to distributor
        int pointer = 0;
        if(storeForLater>0)
          storeForLater--;
        if(rotate) //if rotate is enabled, disable buffering to avoid flushing the buffer in every step
          _disable_buffering();
        for(int y=0;y<width||(rle && storeForLater<=0);y++){
          uchar byte = 0;
          if(rotate)
            byte = _readinbyte_vert(); //Read bytes vertically from the image
          else{
            if(storeForLater<=0) {
              byte = _readinbyte(); //Read byte
              //This block is the procedure that decompresses RLE compressed images
              if(rle && byte!='\n' && byte!='\r'){
                if(byte!='b' && byte!='o' && byte!='$' && byte!='!'){
                  count = count * 10 + (byte - '0'); //Keep counting(e.g 123 = 1 -> 1*10+2 -> 12*10+3 = 123
                }
                if(byte=='!')
                  break;
                if(byte=='b'){ //Fill the array with the number of dead cells counted
                  if(count==0)
                    count = 1;
                  for(int l=0;l<count;l++){
                    changeBit(line, 0, pointer, 0, width);
                    pointer++; //Keep track of where on the uncompressed line are we?
                  }
                  count = 0;
                }
                if(byte=='o'){ //Fill the array with the number of alive cells counted
                  if(count==0)
                    count = 1;
                  for(int l=0;l<count;l++){
                    changeBit(line, 0, pointer, 1, width);
                    pointer++; //Keep track of where on the uncompressed line are we?
                  }
                  count = 0;
                }
                if(byte=='$'){ //Fill the line and add extra lines if needed
                  storeForLater = count; //If we counted more than 1 line, then for the next count-1 iterations, we will be reconstructing those lines
                  for(int l=0;l<(width-pointer);l++){
                    changeBit(line, 0, pointer+l, 0, width);
                  }
                  count = 0;
                  pointer = 0;
                  break;
                }
              }
            }
          }
          if(!rle || storeForLater>0) //This is used when reading a PGM image or when we are filling blank lines in RLE mode
            changeBit(line, 0, y, byte, width);
        }
        //Copy the data from the linebufer to the specified position in the distributor's array.
        memcpy(data+lines2bytes(linenumber,width),line,lines2bytes(1,width));
        break;
      case fromDistributor.end_transfer():
        //Close PGM image file
        _closeinpgm();
        toLeds.send_command(GREEN_LED_OFF);
        break;
  }
 }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// The distributor will execute a syncronization procedure after every round is completed,
// that is, there are no more unprocessed lines stored in its memory + received a signal
// from the slave distributor that the same is true for tile 1 and its workers.
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(client inInterface toDataIn, server outInterface i_out, server accInterface fromAcc,
                 client ledControl toLeds, server d2w workers[n], unsigned n, client d2d slaveDist) {
  uchar data[CHUNK0]; //Allocate a big chunk of memory
  uchar nextTopGhost[MAXLINEBYTES]; //Store the next top ghost row to be given to a worker.
  uchar lineBuffer[MAXLINEBYTES]; //Use that for output
  int height;
  int width;
  int mode = STEP_COMPLETED_MODE; //initially execute the sync procedure
  int nextLineToBeGiven; //The index of the next line to be given to the first worker that asks for data.
  int nextLineToBeAllocated; //This is used to count how many lines have been allocated in total, to workers.
  int linesUpdated = 0; //how many lines have been processed for this round
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

  uchar workersInTile0 = 1;     //How many workers are currently in use in tile 0
  uchar workersInTile0_best = 1;//The number of workers determined to be the most efficient for tile 0
  uchar workersInTile1 = 0;
  uchar workersInTile1_best = 0;
  uchar maxWorkersTile0 = NUMBEROFWORKERSINTILE0;
  uchar maxWorkersTile1 = NUMBEROFWORKERSINTILE1;
  float maxSpeedAchieved = 99999;
  int roundsProcessedWithThisSetup = -1;
  float lastDuration = 0;
  uchar bestFound = 0;

  uchar rotate = 0; //if true, rotate the image by reading it vertically

  //It's always faster to use both tiles
  uchar useTile1 = 0;
  uchar availableWorkers = n; //Total workers
  int linesForD2 = 0;
  int linesForD1 = 0;

  printf("Press button 1 to start.\n");

  //If the format is RLE, then the image cannot be rotated even if required.
  uchar rle = 0;
  {height,width,rle} = toDataIn.initialize_transfer(); //I want data! Also, how big is the image?
  printf("Image size = %dx%d\n", height, width );
  if(!rle && ( (height<12 && width>height) || lines2bytes(1,width)>=MAXLINEBYTES ) ){ //If the image does not fit, or it's too small to make use
    rotate = 1;                                                                       //of all the cores, then read the image vertically(rotate)
    printf("**************WARNING**************\n");
    printf("The system has detected that the image provided has to be\n");
    printf("rotated before processing can begin.\n");
    printf("All I/O operations may be significantly slower!!!\n");
    printf("***********************************\n");
    unsigned int temp = height;
    height = width;
    width = temp;
  }

  //How many rounds should I test for each configuration of cores?
  //The larger the image, the less rounds are needed since it takes more time
  //to process one round.
  int testRounds = keepWithinBounds(3000000/(width * height),5,1000);

  //Use tile 1 if height is larger than 1.
  //This is because one worker in each tile is faster than two workers on
  //1 tile
  if(height>1)
    useTile1 = 1;

  //Decide the maximum amount of workers that can be used.
  //e.g an image with height 8/2=4. Should not use more than 4+4 workers in each tile
  if(useTile1){
    maxWorkersTile0 = keepWithinBounds(height/2,1,NUMBEROFWORKERSINTILE0);
    maxWorkersTile1 = keepWithinBounds(height - maxWorkersTile0,0,NUMBEROFWORKERSINTILE1);
    workersInTile1 = 1; //Initially start with 1 worker and gradually increase
    workersInTile1_best = 1;
  }
  else {
    maxWorkersTile0 = keepWithinBounds(height,1,NUMBEROFWORKERSINTILE0);
    maxWorkersTile1 = 0;
  }
  if(maxWorkersTile1==0){
    workersInTile1 = 0;
    workersInTile1_best = 0;
  }
  slaveDist.set_workers_to(workersInTile1);
  availableWorkers = maxWorkersTile0 + maxWorkersTile1;

  //Since there are more workers in tile 1, try to allocate a bigger part
  //of the image there. The image is divided based on the ratio of workers in tile1 to tile 0
  float ratio = ((float)maxWorkersTile1)/availableWorkers;
  if(ratio==0)
    useTile1 = 0;

  if(useTile1)
    linesForD2 = (int) (ratio*height);
  linesForD1 = height - linesForD2;

  //If the allocated part, does not fit on tile 1, then try
  //giving one more line to tile 0, until the image fits.
  while (lines2bytes(linesForD2+2,width)>CHUNK1){
    if(useTile1)
      linesForD2--;
    linesForD1 = height - linesForD2;
  }

  select{
    case toDataIn.user_input_received(): //When the user presses button 1, a notification is raised. This selects upon that notification
      for( int y = 1; y <= height; y++ ) { //We start from line 1 instead of 0. 0 and the very last position in the array are reserved for ghost rows
          int j;
          if(y<=linesForD2)
            j = 1; //Use line 1 in array as a buffer and send it to slaveDistributor
          else
            j = y - linesForD2; //Then fill the array with the rest of the image.
          toDataIn.request_line(data, j, width, rotate);
          //STARTLINE FOR TILE 0 = linesForD2
          if(y<=linesForD2 && j==1)
            slaveDist.get_data(data, y, width, height);
      }
      toDataIn.end_transfer(); //Clear the notification
      break;
  }

  if(useTile1) {
    slaveDist.exchange_ghosts(data); //Exchange ghost rows if we are using tile 1
  }
  else {
    //Otherwise, just copy the last line to the top and the first to the bottom.
    memcpy(data,data+lines2bytes(linesForD1,width),lines2bytes(1,width));
    memcpy(data+lines2bytes(linesForD1+1,width),data+lines2bytes(1,width),lines2bytes(1,width));
  }

  printf("Processing...\n");
  printf("Adjusting number of workers for highest possible speed...\n");
  //Output and pausing is disabled, so that benchmarking cannot be interrupted.
  printf("Pausing and Output requests are temporarily disabled...\n");

  tmr :> time;
  while(1) {
    if(mode == STEP_COMPLETED_MODE){//ONLY EXECUTE THIS PROCEDURE AT THE BEGINNING OF EACH ROUND
      toLeds.send_command(TOGGLE_SEP_GREEN);
      if(consecutiveRounds == 0) //Take the first measurement
        tmr :> lastPolledTime;
      if(consecutiveRounds == 100){ //After 100 rounds, caculate the time needed and reset the counter
        last100RoundsDuration = lastPolledTime;
        tmr :> lastPolledTime;
        last100RoundsDuration = lastPolledTime - last100RoundsDuration;
        consecutiveRounds = -1;
      }
      if(outputRequested){ //Do we have a request to output the image?
        consecutiveRounds = -1; //Interrupted. Reset the counter
        i_out.data_ready(); //Notify DATA OUT that the round has finished and we are ready to send data
        while(outputRequested){
          select{
            case i_out.request_line(uchar line[], int linenumber): //Serve line requests from DATA OUT
                if(linenumber<linesForD2){//Those lines are in tile 1.
                  slaveDist.get_line(lineBuffer,linenumber);
                  memcpy(line, lineBuffer, lines2bytes(1,width));
                }
                else{
                  memcpy(line,data+lines2bytes(linenumber-linesForD2+1,width),lines2bytes(1,width));
                }
                break;
            case i_out.end_transfer(): //Until end_transfer is called and the notification is cleared
                tmr :> time; //Do not take into account the time spent printing the image
                outputRequested = 0;
                break;
          }
        }
      }
      if (pauseRequested){ //Pause requests?
        toLeds.send_command(RED_LED_ON);
        consecutiveRounds = -1; //Interrupted. Reset the counter
        if(useTile1)
          aliveCellsThisStep = aliveCellsThisStep + slaveDist.get_stats();
        printReport(round,duration,aliveCellsThisStep, width*height, last100RoundsDuration);
        select {
          case fromAcc.unpause():
            pauseRequested = 0;
            tmr :> time; //The time spent paused does not count as processing time.
            toLeds.send_command(RED_LED_OFF);
            break;
        }
      }

      //Reset counters
      nextLineToBeGiven = 1;
      nextLineToBeAllocated = workersInTile0+1; //We start by allocating one line to each worker
      memcpy(nextTopGhost, data, lines2bytes(1,width)); //Initialize the nextTopGhost row array with the first line.
      linesUpdated = 0;
      aliveCellsThisStep = 0;
      round++;
      //Clear the notification raised by slaveDist. Instructs the slave distributor
      //to notify all its workers that data is available.
      if(useTile1)
        slaveDist.start_computation(bestFound);
      //Notify workers in tile 0
      for(int i = 0;i<workersInTile0;i++){
        workers[i].data_ready();
      }

      //This procedure will only run in the beginning of the processing.
      //This is to find the most efficient number of workers to be used.
      //Sometimes, very small images can be processed faster with less workers,
      //due to the communication overhead costing more than the actual processing.
      //We start by testing 1 worker on each tile and then gradually increase the workers.
      consecutiveRounds++;
      roundsProcessedWithThisSetup++;
      if(roundsProcessedWithThisSetup==testRounds && !bestFound){
        float durationWithThisSetup = (duration-lastDuration);
        if(durationWithThisSetup <= maxSpeedAchieved){//keep track of the best configuration
          maxSpeedAchieved = durationWithThisSetup;
          workersInTile0_best = workersInTile0;
          workersInTile1_best = workersInTile1;
        }
        lastDuration = duration;
        roundsProcessedWithThisSetup = 0;
        if((workersInTile0+workersInTile1) == availableWorkers){
          bestFound = 1; //This will also enable dynamic computation. It needs to be disabled for fair benchmarking
          workersInTile0 = workersInTile0_best;
          workersInTile1 = workersInTile1_best;
          slaveDist.set_workers_to(workersInTile1);
          printf("Most efficient number of workers found for tile 0: %d!\n",workersInTile0);
          printf("Most efficient number of workers found for tile 1: %d!\n",workersInTile1);
          printf("Pausing and Output requests are now enabled...\n");
          fflush(stdout);
        }else{
          //Alternate between tile 0 and tile 1 increasing their workers by one.
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
      mode = NEW_STEP_MODE; //NEW ROUND
    }
    select {
      case tmr when timerafter(time) :> void:
          time += 50000000; //Since an integer can only count up to 42 seconds
          duration += 0.5;  //We use a periodic case statement to add 500ms to the duration every 500ms.
          break;
      case bestFound => i_out.initialize_transfer() -> {int outheight, int outwidth, uchar rotateEnable}:
          // An output has been requested. Set outputRequested flag, send the dimensions and whether
          // the image is rotated to Data Out
          outheight = height;
          outwidth = width;
          rotateEnable = rotate;
          outputRequested = 1;
          break;
      case bestFound => fromAcc.pause():
          //Pause requested. Set the flag
          pauseRequested = 1;
          break;
      case workers[int j].get_data(uchar part[])
           -> {int start_line, int lines_sent, int totalCols, uchar speedBoost}:
           //Send the line pointed to by nextLiveToBeGiven to the worker.
           start_line = nextLineToBeGiven;
           lines_sent = 1;
           nextLineToBeGiven = start_line + lines_sent; //Increase the index for the nextLineToBeGiven by 1
           totalCols = width;
           //Copy the top ghost row from the nextTopGhost array
           memcpy(part, nextTopGhost, lines2bytes(1,width));
           //Copy the line to be processed and the bottom ghost row
           memcpy(part + lines2bytes(1,width), data+lines2bytes(start_line,width),lines2bytes(lines_sent+1,width));
           //update nextTopGhost. The line that was just sent, will be the next worker's top row.
           memcpy(nextTopGhost, data+lines2bytes(nextLineToBeGiven-1,width),lines2bytes(1,width));
           speedBoost = bestFound; //Dynamic computation?
           break;
      case workers[int j].send_line(uchar line[], int linenumber, int aliveCells):
          //Fetch the results from the worker and update the main array
          memcpy(data+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesUpdated++; //How many lines have been updated?
          aliveCellsThisStep += aliveCells;
          if(linesUpdated==linesForD1){
            //if done then wait for tile 1 to finish too
            if(useTile1) {
              select{
                case slaveDist.step_completed():
                  //update ghosts for next round
                  slaveDist.exchange_ghosts(data);
                  break;
              }
            }
            else { //if tile 1 is not used, just copy bottom and top rows
              memcpy(data,data+lines2bytes(linesForD1,width),lines2bytes(1,width));
              memcpy(data+lines2bytes(linesForD1+1,width),data+lines2bytes(1,width),lines2bytes(1,width));
            }
            mode = STEP_COMPLETED_MODE; //Round completed
          }
          else if(nextLineToBeAllocated <= linesForD1){
            //if there are more lines to be allocated, then notify the worker that
            //there is more to be processed. This will trigger the worker to request more data
            nextLineToBeAllocated = nextLineToBeAllocated + 1;
            workers[j].data_ready();
          }
          break;
    }
  }
}

void distributor_tile_one(server d2d masterDist, server d2w workers[n], unsigned n) {
  uchar half[CHUNK1];
  uchar nextTopGhost[MAXLINEBYTES];
  int linesReceived = 0, height, width;

  int nextLineToBeGiven;
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
      case masterDist.get_data(uchar data[], int where, int totalCols, int totalRows):
          linesReceived++;
          width = totalCols;
          height = totalRows;
          memcpy(half+lines2bytes(where,width), data+lines2bytes(1,width), lines2bytes(1,width));
          masterDist.step_completed();
          break;
      case masterDist.exchange_ghosts(uchar data[]):
          //Get ghost rows and send yours to master
          //Update top ghost row
          memcpy(half, data+lines2bytes(height-linesReceived,width), lines2bytes(1,width)); //height-linesReceived = linesForD1
          //Update bottom ghost row
          memcpy(half+lines2bytes(linesReceived+1,width), data+lines2bytes(1, width), lines2bytes(1,width));
          //Send top row
          memcpy(data, half+lines2bytes(linesReceived,width), lines2bytes(1,width));
          //Send bottom row
          memcpy(data+lines2bytes(height-linesReceived+1,width), half+lines2bytes(1,width), lines2bytes(1,width));
          break;
      case masterDist.start_computation(uchar sb):
          speedBoost = sb;
          //********************** NOTIFY WORKERS AND INITIALIZE ***************************
          for(int i = 0; i<currentWorkers ;i++){
            workers[i].data_ready();
          }
          nextLineToBeGiven = 1;
          nextLineToBeAllocated = currentWorkers+1;
          memcpy(nextTopGhost, half, lines2bytes(1,width)); //Initialise nextTopGhost row with the very top row of the array
          linesUpdated = 0;
          aliveCellsThisStep = 0;
          break;
      case masterDist.get_line(uchar line[], int linenumber):
          //Put requested line in line buffer. Used for data out
          memcpy(line, half+lines2bytes(linenumber+1,width), lines2bytes(1,width));
          break;
      case masterDist.get_stats() -> {int aliveCells}:
          aliveCells = aliveCellsThisStep;
          break;
      case workers[int j].get_data(uchar part[])
          -> {int start_line, int lines_sent, int totalCols, uchar sb}:
          //Same as tile 0
          sb = speedBoost;
          start_line = nextLineToBeGiven;
          lines_sent = 1;
          nextLineToBeGiven = start_line + lines_sent;
          totalCols = width;
          memcpy(part, nextTopGhost, lines2bytes(1,width));
          memcpy(part + lines2bytes(1,width), half+lines2bytes(start_line,width),lines2bytes(lines_sent+1,width));
          memcpy(nextTopGhost, half+lines2bytes(nextLineToBeGiven-1,width),lines2bytes(1,width)); //update nextTopGhost
          break;
      case workers[int j].send_line(uchar line[], int linenumber, int aliveCells):
          //Fetch the results from the worker and update the main array
          memcpy(half+lines2bytes(linenumber,width), line, lines2bytes(1,width));
          linesUpdated++;
          aliveCellsThisStep += aliveCells;
          if(linesUpdated==linesReceived)
            masterDist.step_completed();
          else if(nextLineToBeAllocated<=linesReceived){
            workers[j].data_ready();
            nextLineToBeAllocated = nextLineToBeAllocated + 1;
          }
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
  uchar neighbours;
  //This is used to pass forward relevant neighbour data from the previous cell's calculation
  uchar right = 255;
  while(1){
    select {
      case distributor.data_ready(): //Wait for data_ready notification
        //Ask for the data. The distributor will copy the data to the array
        {startLine,linesReceived,totalCols,speedBoost} = distributor.get_data(part);
        //Initially we don't have data about the left collumn of the next cell
        right = 255;
        break;
    }

    //PROCESS HERE AND COMMUNICATE EACH LINE
    for(int x=1; x<=linesReceived;x++){ //This is only executed once in the current configuration
      int aliveCells = 0;
      //During the first pass, mark which cells to compute
      if(speedBoost){
        clearBit(line,0,0,totalCols);
        clearBit(line,0,totalCols-1,totalCols);
        uchar markedNext = 0;
        for(int y=0; y<totalCols;y++){
          uchar count = getBit(part, x, y, totalCols);
          count += getBit(part, x-1, y, totalCols);
          count += getBit(part, x+1, y, totalCols);
          //If there are no alive cells in the current column then
          //mark the cell as not necessary to be computed in the next pass
          //unless it was already marked by the previous cell calculation
          //or it is the last cell
          if(count == 0 && y!=totalCols-1 && !markedNext)
            clearBit(line,0,y,totalCols);
          markedNext = 0;
          //If at least one is alive, mark myself for computation
          if(count>0)
            setBit(line, 0, y, totalCols);
          //If more than one, then mark my neighbours too
          if(count>1){
            setBit(line, 0, mod(y-1,totalCols), totalCols);
            setBit(line, 0, mod(y+1,totalCols), totalCols);
            markedNext = 1;//make sure that this mark is not cleared during next iteration
          }
        }
      }
      for(int y=0; y<totalCols;y++){
        //Only compute marked cell, unless dynamic computation is disabled
        if(getBit(line,0,y,totalCols) || !speedBoost){
          uchar itself;
          {neighbours,right,itself} = compute3x3block(part, x, y, totalCols, right);
          uchar res = decide(neighbours, itself);
          aliveCells += (res?1:0); //Count alive cells
          changeBit(line, 0, y, res, totalCols); //Update cell
        }
        else
          right = 255; //Information is useless because we are skipping a cell
      }
      distributor.send_line(line,startLine+x-1,aliveCells); //Send line back to the distributor
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
      case fromDistributor.data_ready()://notification is raised
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
              uchar c =(uchar) (getBit(line,0,x,width)*255); //Extract bit to byte
              if(rotate)
                _writeoutbyte_vert(c);//write vertically to the file using fseek()[SLOW]
              else
                _writeoutbyte(c); //To save space and not use a buffer, write one byte at a time
            }
          }
          _closeoutpgm();
          fromDistributor.end_transfer(); //clears notification
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
      if (x>70 && x<110) {
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
