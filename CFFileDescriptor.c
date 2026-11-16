/*
This file is part of Darling.

Copyright (C) 2026 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// CFFileDescriptor: a run loop source that reports when a file descriptor is readable or writable.
//
// Readiness is watched by libdispatch sources. A source that sees its condition is suspended and the
// run loop source is signaled; when the run loop performs it, the callback is called for the conditions that
// were ready and still enabled, and those conditions are disabled again, so that a callback is delivered
// once per CFFileDescriptorEnableCallBacks.

#include <CoreFoundation/CFFileDescriptor.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFRunLoop.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <unistd.h>
#include "CFInternal.h"

typedef struct __CFFileDescriptor {
    CFRuntimeBase _base;
    pthread_mutex_t lock;
    CFFileDescriptorNativeDescriptor fd;
    Boolean closeOnInvalidate;
    Boolean valid;
    CFFileDescriptorCallBack callout;
    CFFileDescriptorContext context;
    CFOptionFlags enabled;   // callback types the client asked for
    CFOptionFlags ready;     // callback types whose condition was seen and not delivered yet
    CFRunLoopSourceRef source;
    CFMutableArrayRef runLoops; // run loops the source is scheduled in, to wake them up
    dispatch_queue_t queue;
    dispatch_source_t watcher[2]; // read, write
    Boolean watching[2];          // watcher is resumed
} __CFFileDescriptor;

enum { kWatchRead = 0, kWatchWrite = 1 };

static CFOptionFlags watchFlag(int which) {
    return which == kWatchRead ? kCFFileDescriptorReadCallBack : kCFFileDescriptorWriteCallBack;
}

static void wakeRunLoops(CFFileDescriptorRef f) {
    pthread_mutex_lock(&f->lock);
    CFArrayRef loops = f->runLoops ? CFArrayCreateCopy(kCFAllocatorSystemDefault, f->runLoops) : NULL;
    CFRunLoopSourceRef source = f->source ? (CFRunLoopSourceRef)CFRetain(f->source) : NULL;
    pthread_mutex_unlock(&f->lock);
    if (source != NULL) {
        CFRunLoopSourceSignal(source);
        CFRelease(source);
    }
    if (loops != NULL) {
        for (CFIndex i = 0, count = CFArrayGetCount(loops); i < count; i++)
            CFRunLoopWakeUp((CFRunLoopRef)CFArrayGetValueAtIndex(loops, i));
        CFRelease(loops);
    }
}

// Called with the lock held: makes the watcher for one condition run, if it is wanted and not running.
static void startWatching(CFFileDescriptorRef f, int which) {
    if (f->watcher[which] == NULL) {
        dispatch_source_t watcher = dispatch_source_create(which == kWatchRead ? DISPATCH_SOURCE_TYPE_READ : DISPATCH_SOURCE_TYPE_WRITE,
            (uintptr_t)f->fd, 0, f->queue);
        if (watcher == NULL)
            return;
        // The watcher refers to f without retaining it; Invalidate cancels it before f is freed.
        dispatch_source_set_event_handler(watcher, ^{
            pthread_mutex_lock(&f->lock);
            Boolean deliver = f->valid && f->watching[which] && (f->enabled & watchFlag(which));
            if (f->watching[which]) {
                // Wait for the client to enable the callback again before watching more.
                dispatch_suspend(f->watcher[which]);
                f->watching[which] = false;
            }
            if (deliver)
                f->ready |= watchFlag(which);
            pthread_mutex_unlock(&f->lock);
            if (deliver)
                wakeRunLoops(f);
        });
        f->watcher[which] = watcher;
        f->watching[which] = true;
        dispatch_resume(watcher);
        return;
    }
    if (!f->watching[which]) {
        f->watching[which] = true;
        dispatch_resume(f->watcher[which]);
    }
}

static void __CFFileDescriptorPerform(void *info) {
    CFFileDescriptorRef f = (CFFileDescriptorRef)info;
    pthread_mutex_lock(&f->lock);
    CFOptionFlags due = f->ready & f->enabled;
    f->ready = 0;
    f->enabled &= ~due;
    CFFileDescriptorCallBack callout = f->callout;
    Boolean valid = f->valid;
    void *clientInfo = f->context.info;
    void *(*retain)(void *) = f->context.retain;
    void (*release)(void *) = f->context.release;
    pthread_mutex_unlock(&f->lock);
    if (!valid || due == 0 || callout == NULL)
        return;
    if (retain != NULL)
        clientInfo = retain(clientInfo);
    callout(f, due, clientInfo);
    if (release != NULL)
        release(clientInfo);
}

static void __CFFileDescriptorSchedule(void *info, CFRunLoopRef rl, CFStringRef mode) {
    CFFileDescriptorRef f = (CFFileDescriptorRef)info;
    pthread_mutex_lock(&f->lock);
    if (f->runLoops != NULL && CFArrayGetFirstIndexOfValue(f->runLoops, CFRangeMake(0, CFArrayGetCount(f->runLoops)), rl) == kCFNotFound)
        CFArrayAppendValue(f->runLoops, rl);
    Boolean pending = f->ready != 0;
    pthread_mutex_unlock(&f->lock);
    if (pending)
        wakeRunLoops(f);
}

static void __CFFileDescriptorCancel(void *info, CFRunLoopRef rl, CFStringRef mode) {
    CFFileDescriptorRef f = (CFFileDescriptorRef)info;
    pthread_mutex_lock(&f->lock);
    if (f->runLoops != NULL) {
        CFIndex index = CFArrayGetFirstIndexOfValue(f->runLoops, CFRangeMake(0, CFArrayGetCount(f->runLoops)), rl);
        if (index != kCFNotFound)
            CFArrayRemoveValueAtIndex(f->runLoops, index);
    }
    pthread_mutex_unlock(&f->lock);
}

static CFStringRef __CFFileDescriptorCopyDescription(CFTypeRef cf) {
    CFFileDescriptorRef f = (CFFileDescriptorRef)cf;
    return CFStringCreateWithFormat(kCFAllocatorSystemDefault, NULL, CFSTR("<CFFileDescriptor %p [%p]>{valid = %s, fd = %d, enabled = %lu}"),
        cf, CFGetAllocator(cf), f->valid ? "Yes" : "No", f->fd, (unsigned long)f->enabled);
}

static void __CFFileDescriptorDeallocate(CFTypeRef cf) {
    CFFileDescriptorRef f = (CFFileDescriptorRef)cf;
    CFFileDescriptorInvalidate(f);
    if (f->runLoops != NULL)
        CFRelease(f->runLoops);
    if (f->source != NULL)
        CFRelease(f->source);
    if (f->queue != NULL)
        dispatch_release(f->queue);
    pthread_mutex_destroy(&f->lock);
}

static CFTypeID __kCFFileDescriptorTypeID = _kCFRuntimeNotATypeID;

static const CFRuntimeClass __CFFileDescriptorClass = {
    0,
    "CFFileDescriptor",
    NULL,      // init
    NULL,      // copy
    __CFFileDescriptorDeallocate,
    NULL,      // equal
    NULL,      // hash
    NULL,      // copyFormattingDesc
    __CFFileDescriptorCopyDescription
};

CFTypeID CFFileDescriptorGetTypeID(void) {
    static dispatch_once_t initOnce;
    dispatch_once(&initOnce, ^{ __kCFFileDescriptorTypeID = _CFRuntimeRegisterClass(&__CFFileDescriptorClass); });
    return __kCFFileDescriptorTypeID;
}

CFFileDescriptorRef CFFileDescriptorCreate(CFAllocatorRef allocator, CFFileDescriptorNativeDescriptor fd, Boolean closeOnInvalidate,
    CFFileDescriptorCallBack callout, const CFFileDescriptorContext *context)
{
    if (fd < 0)
        return NULL;
    CFIndex size = sizeof(struct __CFFileDescriptor) - sizeof(CFRuntimeBase);
    CFFileDescriptorRef f = (CFFileDescriptorRef)_CFRuntimeCreateInstance(allocator, CFFileDescriptorGetTypeID(), size, NULL);
    if (f == NULL)
        return NULL;
    pthread_mutex_init(&f->lock, NULL);
    f->fd = fd;
    f->closeOnInvalidate = closeOnInvalidate;
    f->callout = callout;
    if (context != NULL) {
        f->context = *context;
        if (context->retain != NULL)
            f->context.info = context->retain(context->info);
    }
    f->runLoops = CFArrayCreateMutable(kCFAllocatorSystemDefault, 0, NULL);
    f->queue = dispatch_queue_create("com.apple.CFFileDescriptor", DISPATCH_QUEUE_SERIAL);
    f->valid = true;
    return f;
}

CFFileDescriptorNativeDescriptor CFFileDescriptorGetNativeDescriptor(CFFileDescriptorRef f) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    return f->fd;
}

void CFFileDescriptorGetContext(CFFileDescriptorRef f, CFFileDescriptorContext *context) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    if (context != NULL)
        *context = f->context;
}

static void changeCallBacks(CFFileDescriptorRef f, CFOptionFlags callBackTypes, Boolean enable) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    pthread_mutex_lock(&f->lock);
    if (f->valid) {
        for (int which = kWatchRead; which <= kWatchWrite; which++) {
            if (!(callBackTypes & watchFlag(which)))
                continue;
            if (enable) {
                f->enabled |= watchFlag(which);
                startWatching(f, which);
            } else {
                f->enabled &= ~watchFlag(which);
                f->ready &= ~watchFlag(which);
            }
        }
    }
    pthread_mutex_unlock(&f->lock);
}

void CFFileDescriptorEnableCallBacks(CFFileDescriptorRef f, CFOptionFlags callBackTypes) {
    changeCallBacks(f, callBackTypes, true);
}

void CFFileDescriptorDisableCallBacks(CFFileDescriptorRef f, CFOptionFlags callBackTypes) {
    changeCallBacks(f, callBackTypes, false);
}

Boolean CFFileDescriptorIsValid(CFFileDescriptorRef f) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    pthread_mutex_lock(&f->lock);
    Boolean valid = f->valid;
    pthread_mutex_unlock(&f->lock);
    return valid;
}

void CFFileDescriptorInvalidate(CFFileDescriptorRef f) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    pthread_mutex_lock(&f->lock);
    if (!f->valid) {
        pthread_mutex_unlock(&f->lock);
        return;
    }
    f->valid = false;
    f->enabled = 0;
    f->ready = 0;
    dispatch_source_t watchers[2] = {f->watcher[0], f->watcher[1]};
    Boolean resumed[2] = {f->watching[0], f->watching[1]};
    f->watcher[0] = f->watcher[1] = NULL;
    f->watching[0] = f->watching[1] = false;
    CFRunLoopSourceRef source = f->source;
    f->source = NULL;
    CFFileDescriptorContext context = f->context;
    memset(&f->context, 0, sizeof(f->context));
    pthread_mutex_unlock(&f->lock);

    // Stop the watchers first, so nothing looks at the descriptor after it is closed.
    dispatch_semaphore_t cancelled = dispatch_semaphore_create(0);
    int pending = 0;
    for (int which = kWatchRead; which <= kWatchWrite; which++) {
        if (watchers[which] == NULL)
            continue;
        dispatch_source_set_cancel_handler(watchers[which], ^{ dispatch_semaphore_signal(cancelled); });
        dispatch_source_cancel(watchers[which]);
        if (!resumed[which])
            dispatch_resume(watchers[which]);
        pending++;
    }
    while (pending-- > 0)
        dispatch_semaphore_wait(cancelled, DISPATCH_TIME_FOREVER);
    dispatch_release(cancelled);
    for (int which = kWatchRead; which <= kWatchWrite; which++) {
        if (watchers[which] != NULL)
            dispatch_release(watchers[which]);
    }

    if (source != NULL) {
        CFRunLoopSourceInvalidate(source);
        CFRelease(source);
    }
    if (f->closeOnInvalidate)
        close(f->fd);
    if (context.release != NULL)
        context.release(context.info);
}

CFRunLoopSourceRef CFFileDescriptorCreateRunLoopSource(CFAllocatorRef allocator, CFFileDescriptorRef f, CFIndex order) {
    __CFGenericValidateType(f, CFFileDescriptorGetTypeID());
    pthread_mutex_lock(&f->lock);
    if (!f->valid) {
        pthread_mutex_unlock(&f->lock);
        return NULL;
    }
    CFRunLoopSourceRef source = f->source;
    if (source != NULL && CFRunLoopSourceIsValid(source) && CFRunLoopSourceGetOrder(source) == order) {
        CFRetain(source);
        pthread_mutex_unlock(&f->lock);
        return source;
    }
    pthread_mutex_unlock(&f->lock);

    CFRunLoopSourceContext sourceContext = {0, (void *)f, NULL, NULL, NULL, NULL, NULL,
        __CFFileDescriptorSchedule, __CFFileDescriptorCancel, __CFFileDescriptorPerform};
    source = CFRunLoopSourceCreate(allocator, order, &sourceContext);
    if (source == NULL)
        return NULL;
    pthread_mutex_lock(&f->lock);
    CFRunLoopSourceRef previous = f->source;
    f->source = (CFRunLoopSourceRef)CFRetain(source);
    pthread_mutex_unlock(&f->lock);
    if (previous != NULL)
        CFRelease(previous);
    return source;
}
