/*
 * helper.h
 *
 *  Created on: Nov 3, 2015
 *      Author: ageorgiou
 */

#ifndef HELPER_H_
#define HELPER_H_

#include "bitArray.h"

#define INITIALIZE_WRITE_OUT 0xAA


int mod(int a, int b){
  int res=a%b;
  if(res<0)
    res += b;
  return res;
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

/*void dumpData(uchar data[], int height, int width, streaming chanend c_out) {
  c_out <: INITIALIZE_WRITE_OUT;
  for( int y = 0; y < height; y++ ) {   //go through all lines
    for( int x = 0; x < width; x++ ) { //go through each pixel per line
      uchar ch = getBit(data, y, x, width);
      //printf("%d ",ch);
      c_out <: (uchar)( ch * 255 ); //send some modified pixel out
    }
    //printf("\n");
  }
}*/

#endif /* HELPER_H_ */
