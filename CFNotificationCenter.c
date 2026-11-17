//
//  CFNotificationCenter.c
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#include "CFBase.h"
#include "CFRuntime.h"
#include "CFNotificationCenter.h"
#include "CFString.h"
#include "CFArray.h"
#include "CFDistributedNotificationInternal.h"
#include <libkern/OSAtomic.h>

struct __CFNotificationCenter {
    CFRuntimeBase _base;
    OSSpinLock lock;
    CFMutableArrayRef observers;
    Boolean distributed;   // the distributed center: observers and notifications go through CFDistributedNotification.c
    Boolean suspended;
};

static void __CFNotificationCenterDeallocate(CFTypeRef cf) {
    struct __CFNotificationCenter *item = (struct __CFNotificationCenter *)cf;
    CFRelease(item->observers);
}

static CFTypeID __kCFNotificationCenterTypeID = _kCFRuntimeNotATypeID;

static const CFRuntimeClass __CFNotificationCenterClass = {
    _kCFRuntimeScannedObject,
    "CFNotificationCenter",
    NULL,   // init
    NULL,   // copy
    __CFNotificationCenterDeallocate,
    NULL,
    NULL,
    NULL,
    NULL
};

static void __CFNotificationCenterInitialize(void) {
    __kCFNotificationCenterTypeID = _CFRuntimeRegisterClass(&__CFNotificationCenterClass);
}

CFTypeID CFNotificationCenterGetTypeID(void) {
    if (__kCFNotificationCenterTypeID == _kCFRuntimeNotATypeID) {
        __CFNotificationCenterInitialize();
    }
    return __kCFNotificationCenterTypeID;
}

typedef struct {
    const void *observer;
    CFNotificationCallback callBack;
    CFStringRef name;
    const void *object;
    CFNotificationSuspensionBehavior suspensionBehavior;
    void *context;
    int32_t retainCount;
} CFNotificationObserver;

static inline CFNotificationObserver *CFNotificationObserverRetain(CFAllocatorRef allocator, CFNotificationObserver *observer) {
    observer->retainCount = OSAtomicIncrement32(&observer->retainCount);
    return observer;
}

static inline void CFNotificationObserverRelease(CFAllocatorRef allocator,CFNotificationObserver *observer) {
    if (OSAtomicDecrement32(&observer->retainCount) < 0) {
        CFRelease(observer->name);
        free(observer);
    }
}

static inline Boolean CFNotificationObserverEqual(CFNotificationObserver *observer1, CFNotificationObserver *observer2) {
    if (observer1 == observer2) {
        return true;
    }

    if (observer1->observer != observer2->observer) {
        return false;
    }
    
    if (observer1->callBack != observer2->callBack) {
        return false;
    }

    if (CFStringCompare(observer1->name, observer2->name, 0) != kCFCompareEqualTo) {
        return false;
    }

    if (observer1->object != observer2->object) {
        return false;
    }

    return true;
}

static struct __CFNotificationCenter *_CFNotificationCenterCreate(CFAllocatorRef allocator) {
    CFIndex size = sizeof(struct __CFNotificationCenter) - sizeof(CFRuntimeBase);
    struct __CFNotificationCenter *center = (struct __CFNotificationCenter *)_CFRuntimeCreateInstance(allocator, CFNotificationCenterGetTypeID(), size, NULL);
    center->lock = OS_SPINLOCK_INIT;
    CFArrayCallBacks callbacks = {
        .version = 0,
        .retain = (CFArrayRetainCallBack)&CFNotificationObserverRetain,
        .release = (CFArrayReleaseCallBack)&CFNotificationObserverRelease,
        .copyDescription = NULL,
        .equal = (CFArrayEqualCallBack)&CFNotificationObserverEqual
    };
    center->observers = CFArrayCreateMutable(allocator, 0, &callbacks);
    return center;
}

static CFNotificationCenterRef localCenter = NULL;
static CFNotificationCenterRef darwinCenter = NULL;
static CFNotificationCenterRef distributedCenter = NULL;
static OSSpinLock centerLock = OS_SPINLOCK_INIT;

CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void) {
    OSSpinLockLock(&centerLock);
    if (localCenter == NULL) {
        localCenter = _CFNotificationCenterCreate(kCFAllocatorDefault);
    }
    OSSpinLockUnlock(&centerLock);
    return localCenter;
}

CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetDarwinNotifyCenter(void) {
    OSSpinLockLock(&centerLock);
    if (darwinCenter == NULL) {
        darwinCenter = _CFNotificationCenterCreate(kCFAllocatorDefault);
    }
    OSSpinLockUnlock(&centerLock);
    return darwinCenter;
}
CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void) {
    OSSpinLockLock(&centerLock);
    if (distributedCenter == NULL) {
        struct __CFNotificationCenter *center = _CFNotificationCenterCreate(kCFAllocatorDefault);
        center->distributed = true;
        distributedCenter = center;
    }
    OSSpinLockUnlock(&centerLock);
    return distributedCenter;
}

CF_EXPORT void CFNotificationCenterAddObserver(CFNotificationCenterRef center, const void *observer, CFNotificationCallback callBack, CFStringRef name, const void *object, CFNotificationSuspensionBehavior suspensionBehavior) {
    if (center->distributed) {
        _CFDistributedAddObserver(observer, callBack, name, (CFStringRef)object, suspensionBehavior);
        return;
    }
    CFNotificationObserver *obs = (CFNotificationObserver *)malloc(sizeof(CFNotificationObserver));
    obs->retainCount = 0;
    obs->observer = observer;
    obs->callBack = callBack;
    obs->name = CFStringCreateCopy(kCFAllocatorDefault, name);
    obs->object = object;
    obs->suspensionBehavior = suspensionBehavior;
    OSSpinLockLock(&center->lock);
    CFArrayAppendValue(center->observers, obs);
    OSSpinLockUnlock(&center->lock);
}

#define __CFMaxRemove 128
struct __CFNotificationRemove {
    CFNotificationObserver* ctx;
    int removed;
    CFIndex removeIdx[__CFMaxRemove];
    int more;
};

void removeObserver(CFNotificationObserver *observer, struct __CFNotificationRemove *notificationRemove) {
    if (notificationRemove->removed == __CFMaxRemove)
    {
        return; // No space for more this pass
    }
    CFNotificationObserver* ctx = notificationRemove->ctx;
    CFNotificationCenterRef center = (CFNotificationCenterRef)ctx->context;
    CFMutableArrayRef observers = center->observers;
    if (observer->observer == ctx->observer) {
        Boolean nameMatches = false;
        Boolean objectMatches = false;
        if (ctx->name != NULL && CFStringCompare(observer->name, ctx->name, 0) == kCFCompareEqualTo) {
            nameMatches = true;
        } else if (ctx->name == NULL) {
            nameMatches = true;
        }
        if (ctx->object != NULL && ctx->object == observer->object) {
            objectMatches = true;
        } else if (ctx->object == NULL) {
            objectMatches = true;
        }
        if (nameMatches && objectMatches) {
            CFIndex idx = CFArrayGetFirstIndexOfValue(observers, CFRangeMake(0, CFArrayGetCount(observers)), observer);
            if (notificationRemove->removed == 0 || idx > notificationRemove->removeIdx[notificationRemove->removed-1]){
                notificationRemove->removeIdx[notificationRemove->removed++] = idx;
            }
            else
            {
                notificationRemove->more++;
            }
        }
    }
}

CF_EXPORT void CFNotificationCenterRemoveObserver(CFNotificationCenterRef center, const void *observer, CFStringRef name, const void *object) {
    if (observer == NULL) {
        return;
    }
    if (center->distributed) {
        _CFDistributedRemoveObserver(observer, name, (CFStringRef)object);
        return;
    }
    OSSpinLockLock(&center->lock);
    CFNotificationObserver ctx = {
        .observer = observer,
        .name = name,
        .object = object,
        .context = center
    };
    struct __CFNotificationRemove notificationRemove = {
        .ctx = &ctx,
        .removed = 0,
        .more = 0
    };
    do {
        CFArrayApplyFunction(center->observers, CFRangeMake(0, CFArrayGetCount(center->observers)), (CFArrayApplierFunction)&removeObserver, &notificationRemove);
        for (int i=notificationRemove.removed-1; i >= 0; i--)
        {
            CFArrayRemoveValueAtIndex(center->observers, notificationRemove.removeIdx[i]);
        }
        if (notificationRemove.removed < __CFMaxRemove && !notificationRemove.more)
        {
            break;
        }
        notificationRemove.removed = 0;
        notificationRemove.more = 0;
    } while(1);
    OSSpinLockUnlock(&center->lock);
}

CF_EXPORT void CFNotificationCenterRemoveEveryObserver(CFNotificationCenterRef center, const void *observer) {
    if (center->distributed) {
        if (observer != NULL) _CFDistributedRemoveObserver(observer, NULL, NULL);
        return;
    }
    OSSpinLockLock(&center->lock);
    CFArrayRemoveAllValues(center->observers);
    OSSpinLockUnlock(&center->lock);
}

CF_EXPORT void CFNotificationCenterPostNotification(CFNotificationCenterRef center, CFStringRef name, const void *object, CFDictionaryRef userInfo, Boolean deliverImmediately) {
    CFNotificationCenterPostNotificationWithOptions(center, name, object, userInfo, deliverImmediately ? kCFNotificationDeliverImmediately : 0);
}

CF_EXPORT void CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterRef center, CFStringRef name, const void *object, CFDictionaryRef userInfo, CFOptionFlags options) {
    if (center->distributed) {
        _CFDistributedPost(name, (CFStringRef)object, userInfo, (options & kCFNotificationDeliverImmediately) != 0);
        return;
    }
    // since this is not cross process, we can just deliver all of the notifs immediately
    OSSpinLockLock(&center->lock);
    CFArrayRef observers = CFArrayCreateCopy(kCFAllocatorDefault, center->observers);
    OSSpinLockUnlock(&center->lock);
    
    CFIndex count = CFArrayGetCount(observers);
    for (CFIndex idx = 0; idx < count; idx++) {
        CFNotificationObserver *observer = (CFNotificationObserver *)CFArrayGetValueAtIndex(observers, idx);
        if (name == NULL || observer->name == NULL || CFStringCompare(observer->name, name, 0) == kCFCompareEqualTo) {
            if (object == NULL || observer->object == NULL || object == observer->object) {
                observer->callBack(center, (void *)observer->observer, name, object, userInfo);
            }
        }
    }
    
    CFRelease(observers);
}


CF_EXPORT void CFNotificationCenterSetSuspended(CFNotificationCenterRef center, Boolean suspended) {
    if (center->distributed) {
        _CFDistributedSetSuspended(suspended);
    }
    center->suspended = suspended;
}

CF_EXPORT Boolean CFNotificationCenterIsSuspended(CFNotificationCenterRef center) {
    return center->distributed ? _CFDistributedIsSuspended() : center->suspended;
}
