/*
 * bitArray.h
 *
 *  Created on: Nov 1, 2015
 *      Author: ageorgiou
 */

#ifndef BITARRAY_H_
#define BITARRAY_H_

typedef unsigned char uchar;

int roundUpToChar(int HEIGHT, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  int numOfBits = HEIGHT * WIDTH;
  return (numOfBits + szc -1) / szc ;
  //return ((n + szc - 1) / szc) * szc;
}

/*
void nullifyExtraBits(){

}
*/

void setBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  int bit = (r*WIDTH)+c;
  int realR = bit/szc;
  int realC = bit%szc;
  A[realR] |= 1 << realC;
}

void clearBit(uchar A[], int r, int c, int WIDTH){
  size_t szc = sizeof(uchar)*8;
  int bit = (r*WIDTH)+c;
  int realR = bit/szc;
  int realC = bit%szc;
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
  int bit = (r*WIDTH)+c;
  int realR = bit/szc;
  int realC = bit%szc;
  return (A[realR] >> realC) & 1;
}


#endif /* BITARRAY_H_ */
