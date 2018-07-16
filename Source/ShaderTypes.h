#pragma once

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

struct Control {
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
    float future[6];
};
