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

