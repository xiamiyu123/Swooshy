#import "CMultitouchShim.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <pthread.h>
#import <stdatomic.h>

typedef void *MTDeviceRef;
typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef, int (*)(int, const SwooshyMTFinger *, int, double, int));
typedef void (*MTDeviceStartFunction)(MTDeviceRef, int);
typedef void (*MTDeviceStopFunction)(MTDeviceRef);

static void *sLibraryHandle = NULL;
static CFMutableArrayRef sDevices = NULL;
static _Atomic(SwooshyMTContactCallback) sClientCallback = NULL;
static _Atomic(void *) sClientContext = NULL;
static pthread_mutex_t sCallbackLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t sCallbackCond = PTHREAD_COND_INITIALIZER;
static int sActiveCallbacks = 0;
static MTDeviceCreateListFunction sMTDeviceCreateList = NULL;
static MTRegisterContactFrameCallbackFunction sMTRegisterContactFrameCallback = NULL;
static MTDeviceStartFunction sMTDeviceStart = NULL;
static MTDeviceStopFunction sMTDeviceStop = NULL;

static bool SwooshyMTHasLoadedSymbols(void) {
    return sLibraryHandle != NULL &&
           sMTDeviceCreateList != NULL &&
           sMTRegisterContactFrameCallback != NULL &&
           sMTDeviceStart != NULL &&
           sMTDeviceStop != NULL;
}

static void SwooshyMTUnloadSymbols(void) {
    if (sLibraryHandle != NULL) {
        dlclose(sLibraryHandle);
    }

    sLibraryHandle = NULL;
    sMTDeviceCreateList = NULL;
    sMTRegisterContactFrameCallback = NULL;
    sMTDeviceStart = NULL;
    sMTDeviceStop = NULL;
}

static void SwooshyMTSetClient(SwooshyMTContactCallback callback, void *context) {
    if (callback == NULL || context == NULL) {
        atomic_store_explicit(&sClientCallback, NULL, memory_order_release);
        atomic_store_explicit(&sClientContext, NULL, memory_order_relaxed);
        return;
    }

    atomic_store_explicit(&sClientContext, context, memory_order_relaxed);
    atomic_store_explicit(&sClientCallback, callback, memory_order_release);
}

static void SwooshyMTCallbackDidEnter(void) {
    pthread_mutex_lock(&sCallbackLock);
    sActiveCallbacks += 1;
    pthread_mutex_unlock(&sCallbackLock);
}

static void SwooshyMTCallbackDidExit(void) {
    pthread_mutex_lock(&sCallbackLock);
    sActiveCallbacks -= 1;
    if (sActiveCallbacks == 0) {
        pthread_cond_broadcast(&sCallbackCond);
    }
    pthread_mutex_unlock(&sCallbackLock);
}

static void SwooshyMTWaitForActiveCallbacks(void) {
    pthread_mutex_lock(&sCallbackLock);
    while (sActiveCallbacks > 0) {
        pthread_cond_wait(&sCallbackCond, &sCallbackLock);
    }
    pthread_mutex_unlock(&sCallbackLock);
}

static int swooshy_mt_callback(int device, const SwooshyMTFinger *data, int fingerCount, double timestamp, int frame) {
    SwooshyMTCallbackDidEnter();
    SwooshyMTContactCallback callback = atomic_load_explicit(&sClientCallback, memory_order_acquire);
    void *context = atomic_load_explicit(&sClientContext, memory_order_relaxed);
    if (callback != NULL && context != NULL) {
        callback(device, data, fingerCount, timestamp, frame, context);
    }
    SwooshyMTCallbackDidExit();
    return 0;
}

static bool SwooshyMTLoadSymbols(void) {
    if (SwooshyMTHasLoadedSymbols()) {
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

    if (!SwooshyMTHasLoadedSymbols()) {
        SwooshyMTUnloadSymbols();
        return false;
    }

    return true;
}

bool SwooshyMTStartMonitoring(SwooshyMTContactCallback callback, void *context) {
    if (callback == NULL || context == NULL) {
        return false;
    }

    if (!SwooshyMTLoadSymbols()) {
        return false;
    }

    SwooshyMTStopMonitoring();

    sDevices = sMTDeviceCreateList();

    if (sDevices == NULL) {
        return false;
    }

    CFIndex count = CFArrayGetCount(sDevices);
    if (count == 0) {
        CFRelease(sDevices);
        sDevices = NULL;
        return false;
    }

    SwooshyMTSetClient(callback, context);
    for (CFIndex index = 0; index < count; index++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(sDevices, index);
        sMTRegisterContactFrameCallback(device, swooshy_mt_callback);
        sMTDeviceStart(device, 0);
    }

    return true;
}

void SwooshyMTStopMonitoring(void) {
    SwooshyMTSetClient(NULL, NULL);
    SwooshyMTWaitForActiveCallbacks();

    if (sDevices != NULL && sMTDeviceStop != NULL) {
        CFIndex count = CFArrayGetCount(sDevices);
        for (CFIndex index = 0; index < count; index++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(sDevices, index);
            sMTDeviceStop(device);
        }
        CFRelease(sDevices);
        sDevices = NULL;
    }
}
