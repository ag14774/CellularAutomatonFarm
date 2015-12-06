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

//****Bits in the 4-bit led pattern****
#define NO_LED         0
#define SEP_GREEN_LED  1
#define BLUE_LED       2
#define GREEN_LED      4
#define RED_LED        8
//*************************************

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

/**
 * Computes a 3x3 block. Takes an array and the cell that is the centre of that block
 * @param A Array that holds a line of the image
 * @param r Row of the centre cell
 * @param c Collumn of the centre cell
 * @param width
 * @param left Do we already know anything about the left collumn or should I compute it all over again?
 * @return # of alive neighbours
 *         Is the centre cell alive
 *         Data that should be passed to the next cell to avoid recomputation
 */
{uchar,uchar,uchar} compute3x3block(uchar A[], int r, int c, int width, uchar left){
  uchar res = 0;
  if(left != 255)
    res = left;
  uchar aliveRight = 0;
  uchar alive = 0;
  uchar itself;

  //Only compute if results are not given by previous computation
  if(left==255){
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
  itself = alive;

  alive = getBitToroidal(A, r+1, c, width);
  res+=alive;
  aliveRight += alive;

  alive = getBitToroidal(A, r-1, c+1, width);
  res+=alive;

  alive = getBitToroidal(A, r, c+1, width);
  res+=alive;

  alive = getBitToroidal(A, r+1, c+1, width);
  res+=alive;


  return {res,aliveRight,itself};
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
