#ifndef PGMIO_H_
#define PGMIO_H_

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int _getheight();
int _getwidth();

int _openinpgm(char fname[]);
unsigned char _readinbyte();
unsigned char _readinbyte_vert();
int _closeinpgm();

int _openoutpgm(char fname[], int width, int height);
int _writeoutbyte(unsigned char c);
int _writeoutbyte_vert(unsigned char c);
int _closeoutpgm();

int _disable_buffering();

#endif /*PGMIO_H_*/
