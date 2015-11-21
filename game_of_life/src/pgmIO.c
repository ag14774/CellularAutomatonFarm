#include "pgmIO.h"

FILE *_INFP = NULL;
FILE *_OUTFP = NULL;
int inwidth;
int inheight;
int x;
int xout;

/////////////////////////////////////////////////////////////////////////////////////////////
//Line-wise pgm in:
int _openinpgm(char fname[])
{
	char str[ 64 ];

	_INFP = fopen( fname, "rb" );
	if( _INFP == NULL )
	{
		printf( "Could not open %s.\n", fname );
		return -1;
	}
	//Strip off header
    fgets( str, 64, _INFP ); //Version: P5
    fgets( str, 64, _INFP ); //width and height
    sscanf( str, "%d%d", &inwidth, &inheight );
/*    if( inwidth != width || inheight != height )
    {
    	printf( "Input image size(%dx%d) does not = %dx%d or trouble reading header\n", inwidth, inheight, width, height );
    	return -1;
    }*/
    fgets( str, 64, _INFP ); //bit depth, must be 255
    x = 0;
	return 0;
}

int _getheight(){
  return inheight;
}

int _getwidth(){
  return inwidth;
}

unsigned char _readinbyte() {
  int nb;
  unsigned char byte;

  if( _INFP == NULL )
  {
    return -1;
  }

  nb = fread( &byte, 1, 1, _INFP );

  if( nb != 1 )
  {
    //printf( "Error reading byte, nb = %d\n", nb );
    //Error or end of file
    return -1;
  }
  return byte;
}

int _disable_buffering(){
  return setvbuf(_INFP, 0, _IONBF, 0);
}

unsigned char _readinbyte_vert() {
  int nb;
  unsigned char byte;

  if( _INFP == NULL )
  {
    return -1;
  }

  nb = fread( &byte, 1, 1, _INFP );

  if( nb != 1 )
  {
    //printf( "Error reading byte, nb = %d\n", nb );
    //Error or end of file
    return -1;
  }

  if(x==inheight-1){
    x = 0;
    fseek(_INFP, -(inheight-1)*inwidth, SEEK_CUR);
  }
  else {
    nb = fseek(_INFP, inwidth-1, SEEK_CUR);
    x++;
  }

  return byte;
}

int _readinline(unsigned char line[], int width)
{
	int nb;

	if( _INFP == NULL )
	{
		return -1;
	}

	nb = fread( line, 1, width, _INFP );

	if( nb != width )
	{
		//printf( "Error reading line, nb = %d\n", nb );
		//Error or end of file
		return -1;
	}
	return 0;
}

int _closeinpgm()
{
	int ret = fclose( _INFP );
	if( ret == 0 )
	{
		_INFP = NULL;
	}
	else
	{
		printf( "Error closing file _INFP.\n" );
	}
	return ret; //return zero for succes and EOF for fail
}

/////////////////////////////////////////////////////////////////////////////////////////////
//Line-wise pgm out:
int _openoutpgm(char fname[], int width, int height)
{
  char hdr[ 64 ];

	_OUTFP = fopen( fname, "wb" );
	if( _OUTFP == NULL )
	{
		printf( "Could not open %s.\n", fname );
		return -1;
	}

  sprintf( hdr, "P5\n%d %d\n255\n", width, height );
  fprintf( _OUTFP, "%s", hdr );

  xout = 0;
	return 0;
}

int _writeoutline(unsigned char line[], int width)
{
	int nb;

	if( _OUTFP == NULL )
	{
		return -1;
	}

	nb = fwrite( line, 1, width, _OUTFP );

	if( nb != width )
	{
		//printf( "Error writing line, nb = %d\n", nb );
		//Error or end of file
		return -1;
	}
	return 0;
}

int _writeoutbyte_vert(unsigned char c){
  int nb;

  if( _OUTFP == NULL )
  {
    return -1;
  }

  nb = fwrite( &c, 1, 1, _OUTFP );

  if( nb != 1 )
  {
    //printf( "Error writing byte, nb = %d\n", nb );
    //Error or end of file
    return -1;
  }

  if(xout==inheight-1){
    xout = 0;
    fseek(_OUTFP, -(inheight-1)*inwidth, SEEK_CUR);
  }
  else {
    nb = fseek(_OUTFP, inwidth-1, SEEK_CUR);
    xout++;
  }

  return 0;
}

int _writeoutbyte(unsigned char c)
{
  int nb;

  if( _OUTFP == NULL )
  {
    return -1;
  }

  nb = fwrite( &c, 1, 1, _OUTFP );

  if( nb != 1 )
  {
    //printf( "Error writing byte, nb = %d\n", nb );
    //Error or end of file
    return -1;
  }
  return 0;
}

int _closeoutpgm()
{
	int ret = fclose( _OUTFP );
	if( ret == 0 )
	{
		_OUTFP = NULL;
	}
	else
	{
		printf( "Error closing file _OUTFP.\n" );
	}
	return ret; //return zero for succes and EOF for fail
}

/////////////////////////////////////////////////////////////////////////////////////////////
//Standard pgm IO:

//Input is a referenced array of unsigned chars of width and height and a
//referenced char array of the system path to destination, e.g.
//"/home/user/xmos/project/" on Linux or "C:\\user\\xmos\\project\\" on Windows
int _writepgm(unsigned char x[], int height, int width, char fname[])
{
    FILE *fp;
    int hlen;
    char hdr[ 64 ];

    sprintf( hdr, "P5\n%d %d\n255\n", width, height );
    hlen = strlen( hdr );
	printf( "In writepgm function, writing: %s\n", fname );

	fp = fopen( fname, "wb" );
	if( fp == NULL)
	{
		printf( "Could not open %s for writing.\n", fname );
		return -1;
	}
    fprintf( fp, "%s", hdr );
    fwrite( x, width * height, 1, fp );
    fclose( fp );
    return 0;
}

int _readpgm(unsigned char x[], int height, int width, char fname[])
{
    FILE *fp;
    int inwidth, inheight;
    char str[ 64 ];

	printf( "In readpgm function, reading: %s\n", fname );

	fp = fopen( fname, "rb" );
	if( fp == NULL)
	{
		printf( "Could not open %s for reading.\n", fname );
		return -1;
	}
    fgets( str, 64, fp ); //Version: P5
    fgets( str, 64, fp ); //width and height
    sscanf( str, "%d%d", &inwidth, &inheight );
    fgets( str, 64, fp ); //bit depth, must be 255
    if( inwidth != width || inheight != height )
    {
    	printf( "Input image size(%dx%d) does not = %dx%d or trouble reading header\n", inwidth, inheight, width, height );
    	return -1;
    }
    fread( x, inwidth * inheight, 1, fp );
    fclose( fp );
    return 0;
}
