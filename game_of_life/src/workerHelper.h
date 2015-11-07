/*
 * workerHelper.h
 *
 *  Created on: Nov 3, 2015
 *      Author: ageorgiou
 */

#ifndef WORKERHELPER_H_
#define WORKERHELPER_H_

#include "bitArray.h"

/*
#define FEEDING_MODE        0x00
#define GHOST_EXCHANGE_MODE 0x01
#define PROCESSING_MODE     0x02
#define BLEEDING_MODE       0x03

//Distributor is required to sign a message both at
//the beginning and the end
#define DISTR_CODE          0xFF
#define WORKER_POINTER      0xD0
//worker0  = 0xD0
//worker1  = 0xD1
//..
//worker15 = 0xDF
#define WORKER_ABOVE        0xE0
#define WORKER_BELOW        0xE1

#define ERROR_CODE          0xEE

#define START_END_SIGNAL    0xFF
*/


int mod(int a, int b){
  int res=a%b;
  if(res<0)
    res += b;
  return res;
}

/*uint8_t workerCode(int n){
  if(n>15 || n<0) {
    printf("WORKERS ALLOWED: 0-15\n");
    return ERROR_CODE;
  }
  return WORKER_POINTER + n;
}

void sendLineTo(uchar workerNumber, streaming chanend toDist, uchar A[], int line, int length){
  if(workerNumber==WORKER_ABOVE || workerNumber == WORKER_BELOW)
    toDist <: workerNumber;
  else
    toDist <: workerCode(workerNumber);
  for(int i=0;i<length;i++){
    toDist <: getBit(A, line, i, length);
  }
}

void receiveLineFrom(streaming chanend from, uchar A[], int line, int length){
  uchar a;
  for(int i=0;i<length;i++){
    from :> a;
    changeBit(A, line, i, a, length);
  }
}*/

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

#endif /* WORKERHELPER_H_ */
