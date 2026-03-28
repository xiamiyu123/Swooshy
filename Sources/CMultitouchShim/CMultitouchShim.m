#import "CMultitouchShim.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

typedef void *MTDeviceRef;
typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef, int (*)(int, const SweeeshMTFinger *, int, double, int));
typedef void (*MTDeviceStartFunction)(MTDeviceRef, int);
typedef void (*MTDeviceStopFunction)(MTDeviceRef);

static void *sLibraryHandle = NULL;
static CFMutableArrayRef sDevices = NULL;
static SweeeshMTContactCallback sClientCallback = NULL;
static void *sClientContext = NULL;
static MTDeviceCreateListFunction sMTDeviceCreateList = NULL;
static MTRegisterContactFrameCallbackFunction sMTRegisterContactFrameCallback = NULL;
static MTDeviceStartFunction sMTDeviceStart = NULL;
static MTDeviceStopFunction sMTDeviceStop = NULL;

static int sweeesh_mt_callback(int device, const SweeeshMTFinger *data, int fingerCount, double timestamp, int frame) {
    if (sClientCallback != NULL) {
        sClientCallback(device, data, fingerCount, timestamp, frame, sClientContext);
    }
    return 0;
}

static bool SweeeshMTLoadSymbols(void) {
    if (sLibraryHandle != NULL) {
        return true;
    }

    sLibraryHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (sLibraryHandle == NULL) {
        return false;
    }

    sMTDeviceCreateList = (MTDeviceCreateListFunction)dlsym(sLibraryHandle, "MTDeviceCreateList");
    sMTRegisterContactFrameCallback = (MTRegisterContactFrameCallbackFunction)dlsym(sLibraryHandle, "MTRegisterContactFrameCallback");
    sMTDeviceStart = (MTDeviceStartFunction)dlsym(sLibraryHandle, "MTDeviceStart");
    sMTDeviceStop = (MTDeviceStopFunction)dlsym(sLibraryHandle, "MTDeviceStop");

    return sMTDeviceCreateList != NULL &&
           sMTRegisterContactFrameCallback != NULL &&
           sMTDeviceStart != NULL &&
           sMTDeviceStop != NULL;
}

bool SweeeshMTStartMonitoring(SweeeshMTContactCallback callback, void *context) {
    if (!SweeeshMTLoadSymbols()) {
        return false;
    }

    SweeeshMTStopMonitoring();

    sClientCallback = callback;
    sClientContext = context;
    sDevices = sMTDeviceCreateList();

    if (sDevices == NULL) {
        return false;
    }

    CFIndex count = CFArrayGetCount(sDevices);
    for (CFIndex index = 0; index < count; index++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(sDevices, index);
        sMTRegisterContactFrameCallback(device, sweeesh_mt_callback);
        sMTDeviceStart(device, 0);
    }

    return count > 0;
}

void SweeeshMTStopMonitoring(void) {
    if (sDevices != NULL && sMTDeviceStop != NULL) {
        CFIndex count = CFArrayGetCount(sDevices);
        for (CFIndex index = 0; index < count; index++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(sDevices, index);
            sMTDeviceStop(device);
        }
        CFRelease(sDevices);
        sDevices = NULL;
    }

    sClientCallback = NULL;
    sClientContext = NULL;
}
