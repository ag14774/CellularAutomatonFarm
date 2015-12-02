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

int min(int a, int b){
  if(a<b)
    return a;
  return b;
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

{uchar,uchar} countAliveNeighbours(uchar A[], int r, int c, int width, uchar right){
  uchar res = 0;
  if(right != 255)
    res = right;
  uchar aliveRight = 0;
  uchar alive = 0;

  if(right==255){
    alive = getBitToroidal(A, r-1, c-1, width);
    res+=alive;
    alive = getBitToroidal(A, r, c-1, width);
    res+=alive;
    alive = getBitToroidal(A, r+1, c-1, width);
    res+=alive;
  }

  alive = getBitToroidal(A, r-1, c, width);
  res+=alive;
  aliveRight += alive;

  alive = getBitToroidal(A, r, c, width);
  aliveRight += alive;

  alive = getBitToroidal(A, r+1, c, width);
  res+=alive;
  aliveRight += alive;

  alive = getBitToroidal(A, r-1, c+1, width);
  res+=alive;

  alive = getBitToroidal(A, r, c+1, width);
  res+=alive;

  alive = getBitToroidal(A, r+1, c+1, width);
  res+=alive;


  return {res,aliveRight};
}

void printReport(long round, float duration, int aliveCells, int totalCells, unsigned int last100RoundsDuration){
  unsigned int minutes;
  unsigned int seconds;
  unsigned long cellsPerSecond;
  minutes = (int)duration / 60;
  seconds = (int)duration % 60;
  double last100DurationInSeconds = last100RoundsDuration/100000000.0f;
  if(last100DurationInSeconds!=0){
    double roundsPerSecond = 100.0 / last100DurationInSeconds;
    cellsPerSecond = roundsPerSecond * totalCells;
  } else {
    cellsPerSecond = 0;
  }
  printf("----------------STATUS REPORT----------------\n");
  printf("| Rounds processed : %-24u|\n",round);
  printf("| Processing time  : %02dm %02ds%18|\n", minutes, seconds);
  printf("| # of alive cells : %-24u|\n",aliveCells);
  printf("| Processing speed : %010u cells/sec%5|\n",cellsPerSecond);
  printf("---------------------------------------------\n");
}

#endif /* HELPER_H_ */
