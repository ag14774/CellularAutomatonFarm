/*
 * bitArray.h
 *
 *  Created on: Nov 1, 2015
 *      Author: ageorgiou
 */

#ifndef BITARRAY_H_
#define BITARRAY_H_

typedef unsigned char uchar;

int roundUpToChar(int n){
  size_t szc = sizeof(char);
  return ((n + scz - 1) / scz) * scz;
}

void setBit(uchar A[], int r, int c, int WIDTH){
  int bit = (r*WIDTH)+c;
  int realR = bit/sizeof(uchar);
  int realC = bit%sizeof(uchar);
  A[realR] |= 1 << realC;
}

void clearBit(uchar A[], int r, int c, int WIDTH){
  int bit = (r*WIDTH)+c;
  int realR = bit/sizeof(uchar);
  int realC = bit%sizeof(uchar);
  A[realR] &= ~(1 << realC);
}

void changeBit(uchar A[], int r, int c, int changeTo, int WIDTH){
  if(changeTo){
    setBit(A, r, c, WIDTH);
  } else {
    clearBit(A, r, c, WIDTH);
  }
}

int getBit(uchar A[], int r, int c, int WIDTH){
  int bit = (r*WIDTH)+c;
  int realR = bit/sizeof(uchar);
  int realC = bit%sizeof(uchar);
  int bit = (A[realR] >> realC) & 1;
  return bit;
}


#endif /* BITARRAY_H_ */
