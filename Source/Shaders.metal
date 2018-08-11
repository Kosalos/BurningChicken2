// for info on Point and Line orbit traps visit:
// http://www.iquilezles.org/www/articles/ftrapsgeometric/ftrapsgeometric.htm

#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

float2 complexMul(float2 v1, float2 v2) { return float2(v1.x * v2.x - v1.y * v2.y, v1.x * v2.y + v1.y * v2.x); }

kernel void fractalShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 constant float3 *color [[buffer(1)]],          // color lookup table[256]
 uint2 p [[thread_position_in_grid]])
{
    if(p.x > uint(control.xSize)) return; // screen size not evenly divisible by threadGroups
    if(p.y > uint(control.ySize)) return;

    float2 c = float2(control.xmin + control.dx * float(p.x), control.ymin + control.dy * float(p.y));
    int iter;
    int maxIter = int(control.maxIter);
    int skip = int(control.skip);
    float avg = 0;
    float lastAdded = 0;
    float count = 0;
    float2 z = float2();
    float z2 = 0;
    float minDist = 999;

    for(iter = 0;iter < maxIter;++iter) {
        z = complexMul(z,z) + c;
        
        if(control.coloringFlag && (iter >= skip)) {
            count += 1;
            lastAdded = 0.5 + 0.5 * sin(control.stripeDensity * atan2(z.y, z.x));
            avg += lastAdded;
        }

        if(control.chickenFlag && z.y < 0) { z.y = -z.y; }

        // point,line orbit traps ------------------------------------------
        for(int i=0;i<3;++i) {
            if(control.pTrap[i].active) {
                float dist = length(z - float2(control.pTrap[i].x,control.pTrap[i].y));
                minDist = min(minDist, dist * dist);
            }
            if(control.lTrap[i].active) {
                float A = z.x - control.lTrap[i].x;
                float B = z.y - control.lTrap[i].y;
                float C = 1;  // x2 - x1
                float D = control.lTrap[i].slope; // y2 - y1
                float dist = abs(A * D - C * B) / sqrt(C * C + D * D);
                
                minDist = min(minDist, dist * dist);
            }
        }
        // -----------------------------------------------------------------
        
        z2 = dot(z,z);
        if (z2 > control.escapeRadius && iter > skip) break;
    }
    
    float3 icolor = float3();

    if(control.coloringFlag) {
        float fracDen = (minDist > 900) ? log(z2) : minDist * minDist;
        
        if(count > 1) {
            float prevAvg = (avg - lastAdded) / (count - 1.0);
            avg = avg / count;
            
            float frac = 1.0 + (log2(log(control.escapeRadius) / fracDen));
            float mix = frac * avg + (1.0 - frac) * prevAvg;
        
            if(iter < maxIter) {
                float co = mix * pow(10.0,control.multiplier);
                co = clamp(co,0.0,10000.0) * 6.2831;
                icolor.x = 0.5 + 0.5 * cos(co + control.R);
                icolor.y = 0.5 + 0.5 * cos(co + control.G);
                icolor.z = 0.5 + 0.5 * cos(co + control.B);
            }
        }
    }
    else {
        iter = (minDist > 900) ? iter * 2 : int(minDist * minDist);
        if(iter < 0) iter = 0; else if(iter > 255) iter = 255;
        
        icolor = color[iter];
    }
    
    icolor.x = 0.5 + (icolor.x - 0.5) * control.contrast;
    icolor.y = 0.5 + (icolor.y - 0.5) * control.contrast;
    icolor.z = 0.5 + (icolor.z - 0.5) * control.contrast;

    outTexture.write(float4(icolor,1),p);
    
}

// ======================================================================

kernel void shadowShader
(
 texture2d<float, access::read> src [[texture(0)]],
 texture2d<float, access::write> dst [[texture(1)]],
 uint2 p [[thread_position_in_grid]])
{
    float4 v = src.read(p);
    
    if(p.x > 1 && p.y > 1) {
        bool shadow = false;
        
        {
            uint2 p2 = p;
            p2.x -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(!shadow)
        {
            uint2 p2 = p;
            p2.x -= 1;
            p2.y -= 1;
            float4 vx = src.read(p2);
            if(v.x < vx.x || v.y < vx.y) shadow = true;
        }
        
        if(shadow) {
            v.x /= 4;
            v.y /= 4;
            v.z /= 4;
        }
    }
    
    dst.write(v,p);
}
