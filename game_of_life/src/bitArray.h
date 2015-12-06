/*
 * bitArray.h
 *
 *  Created on: Nov 1, 2015
 *      Author: ageorgiou
 */

#ifndef BITARRAY_H_
#define BITARRAY_H_

typedef unsigned char uchar;

/**
 * Normal mod function because C's '%' is weird with negative numbers
 */
int mod(int a, int b){
  int result = a%b;
  if(result<0){
    return result+b;
  }
  return result;
}

void setBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8; //A byte is 8 bits
  size_t bytesPerLine = (WIDTH + szc - 1) / szc; //Round up to the nearest byte.
  int realR = r*bytesPerLine + c/8; //Real row in the one dimensional array
  int realC = c%8; //Where in the byte is this cell?
  A[realR] |= 1 << realC; //Use or to set the bit
}

void clearBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int realR = r*bytesPerLine + c/8;
  int realC = c%8;
  A[realR] &= ~(1 << realC); //Use AND to clear the bit
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
  return (A[realR] >> realC) & 1; //Use AND to get the bit
}

/**
 * Convert from lines to bytes.
 */
int lines2bytes(int lines, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  size_t bytesPerLine = (WIDTH + szc - 1) / szc;
  int res = lines*bytesPerLine;
  return res;
}

#endif /* BITARRAY_H_ */
