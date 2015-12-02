/*
 * bitArray.h
 *
 *  Created on: Nov 1, 2015
 *      Author: ageorgiou
 */

#ifndef BITARRAY_H_
#define BITARRAY_H_

#include "debug_print.h"

typedef unsigned char uchar;

int mod(int a, int b){
  int result = a%b;
  if(result<0){
    return result+b;
  }
  return result;
}

void setBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int realR = r*bytesPerLine + c/8;
  int realC = c%8;
  A[realR] |= 1 << realC;
}

void clearBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int realR = r*bytesPerLine + c/8;
  int realC = c%8;
  A[realR] &= ~(1 << realC);
}

void changeBit(uchar A[], int r, int c, uchar changeTo, int WIDTH){
  if(changeTo){
    setBit(A, r, c, WIDTH);
  } else {
    clearBit(A, r, c, WIDTH);
  }
}

uchar getBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int realR = r*bytesPerLine + c/8;
  int realC = c%8;
  return (A[realR] >> realC) & 1;
}

int lines2bytes(int line, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int realR = line*bytesPerLine;
  return realR;
}

#endif /* BITARRAY_H_ */
