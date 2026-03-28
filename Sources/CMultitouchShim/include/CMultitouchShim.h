#ifndef CMULTITOUCHSHIM_H
#define CMULTITOUCHSHIM_H

#include <stdbool.h>

typedef struct {
    float x;
    float y;
} SweeeshMTPoint;

typedef struct {
    SweeeshMTPoint position;
    SweeeshMTPoint velocity;
} SweeeshMTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int unknown1;
    int unknown2;
    SweeeshMTVector normalized;
    float size;
    int unknown3;
    float angle;
    float majorAxis;
    float minorAxis;
    SweeeshMTVector millimeters;
    int unknown5_1;
    int unknown5_2;
    float unknown6;
} SweeeshMTFinger;

typedef void (*SweeeshMTContactCallback)(
    int device,
    const SweeeshMTFinger *data,
    int fingerCount,
    double timestamp,
    int frame,
    void *context
);

bool SweeeshMTStartMonitoring(SweeeshMTContactCallback callback, void *context);
void SweeeshMTStopMonitoring(void);

#endif
