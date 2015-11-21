/*
 * helper.h
 *
 *  Created on: Nov 3, 2015
 *      Author: ageorgiou
 */

#ifndef HELPER_H_
#define HELPER_H_

#define STEP_COMPLETED_MODE  0xAA
#define NEW_STEP_MODE        0xAB

#define NO_LED         0
#define SEP_GREEN_LED  1
#define BLUE_LED       2
#define GREEN_LED      4
#define RED_LED        8

#define SEP_GREEN_OFF    0xF0
#define SEP_GREEN_ON     0xF1
#define BLUE_LED_OFF     0xF2
#define BLUE_LED_ON      0xF3
#define GREEN_LED_OFF    0xF4
#define GREEN_LED_ON     0xF5
#define RED_LED_OFF      0xF6
#define RED_LED_ON       0xF7

#define TOGGLE_SEP_GREEN 0xF8

#include "bitArray.h"

int keepWithinBounds(int num, int low, int high){
  if(num>high)
    return high;
  if(num<low)
    return low;
  return num;
}

uchar decide(int aliveNeighbours, uchar itselfAlive){
  if(aliveNeighbours<2)
    return 0;
  if(aliveNeighbours>3)
    return 0;
  if(aliveNeighbours==3)
    return 1;
  return itselfAlive;
}

uchar getBitToroidal(uchar A[], int r, int c, int width){
  if(c==-1)
    c = width-1;
  if(c==width)
    c = 0;
  return getBit(A, r, c, width);
}

int countAliveNeighbours(uchar A[], int r, int c, int width){
  int topLeftX = r - 1;
  int topLeftY = c - 1;
  int botRightX = r + 1;
  int botRightY = c + 1;
  int res = 0;
  uchar itself = getBit(A, r, c, width);
  for(int x = topLeftX ; x<=botRightX ; x++){
    for(int y = topLeftY ; y<=botRightY ; y++){
      res += getBitToroidal(A, x, y, width);
    }
  }
  return res - itself;
}

uint8_t calculateMinimumCores(unsigned int memoryPerWorker, unsigned int lines, unsigned int width){
  if(lines == 0)
    return 0;
  uint8_t n = 0;
  unsigned int linesPerWorker;
  unsigned int extraLines;
  do {
      n++;
      linesPerWorker = lines / n;
      extraLines     = lines % n;
  } while(lines2bytes(2+linesPerWorker+(extraLines>0?1:0),width)>memoryPerWorker);
//  printf("Minimum possible cores: %d\n", n);
  return n;
}

void printReport(long round, float duration, int aliveCells, int totalCells){
  unsigned int minutes;
  unsigned int seconds;
  minutes = (int)duration / 60;
  seconds = (int)duration % 60;
  double roundsPerSecond = ((double)round) / duration;
  unsigned long cellsPerSecond = roundsPerSecond * totalCells;
  printf("----------------STATUS REPORT----------------\n");
  printf("| Rounds processed: %-24u|\n",round);
  printf("| Processing time : %02dm %02ds%18|\n", minutes, seconds);
  printf("| # of alive cells: %-24u|\n",aliveCells);
  printf("| Processing speed: %010u cells/sec%5|\n",cellsPerSecond);
  printf("---------------------------------------------\n");
}

#endif /* HELPER_H_ */
