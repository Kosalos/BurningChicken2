#pragma once
#include <simd/simd.h>

typedef struct {
    float x,y;
    int active;
} PointOrbitTrap;

typedef struct {
    float x,y;
    float slope;
    int active;
} LineOrbitTrap;

typedef struct {
    int version;
    int xSize,ySize;
    
    float xmin,xmax,dx;
    float ymin,ymax,dy;

    int coloringFlag;
    int chickenFlag;
    
    float maxIter;
    float skip;
    float stripeDensity;
    float escapeRadius;
    float multiplier;
    float R;
    float G;
    float B;
    float contrast;
    
    PointOrbitTrap pTrap[3];
    LineOrbitTrap lTrap[3];
    
    float power;
    float future[5];
} Control;

#ifndef __METAL_VERSION__

void setControlPointer(Control *ptr);

void setPTrapActive(int index, int onoff);
void setLTrapActive(int index, int onoff);
int  getPTrapActive(int index);
int  getLTrapActive(int index);
void togglePointTrap(int index);
void toggleLineTrap(int index);

float* PTrapX(int index);
float* PTrapY(int index);
float* LTrapX(int index);
float* LTrapY(int index);
float* LTrapS(int index);

#endif

