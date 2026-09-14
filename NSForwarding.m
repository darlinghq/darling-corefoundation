/*
This file is part of Darling.

Copyright (C) 2017-2019 Lubos Dolezel

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

//
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <CoreFoundation/CFLogUtilities.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>

#import "NSObjCRuntimeInternal.h"
#import "NSZombie.h"

#import <objc/runtime.h>
#import <stdio.h>

#import "NSBlockInvocationInternal.h"

#define ALIGN_TO(value, alignment) \
    (((value) % (alignment)) ? \
    ((value) + (alignment) - ((value) % (alignment))) : \
    (value) \
)

static void __NSForwardSignatureError() { __builtin_trap(); }

struct objc_sendv_margs {
    uintptr_t a[4];
    uintptr_t stackArgs[];
};

// indirectResult is the caller's x8 on arm64 (unused elsewhere).
id ___forwarding___(struct objc_sendv_margs *args, void *returnStorage, void *indirectResult)
{
    id self = (id)args->a[0];
    SEL _cmd = (SEL)args->a[1];
    Class class = object_getClass(self);

    const char *className = class_getName(class);

    if (strncmp(className, ZOMBIE_PREFIX, strlen(ZOMBIE_PREFIX)) == 0)
    {
        const char* origClassName = &className[strlen(ZOMBIE_PREFIX)];
        const char* selName = sel_getName(_cmd);
        printf("-[%s %s] message sent to deallocated instance %p.\n", origClassName, selName, self);
#if defined(__i386__) || defined(__x86_64__)
        __asm__ volatile("int $0x03");
#elif defined(__thumb__)
        __asm__ volatile(".inst 0xde01");
#elif defined(__arm__) && !defined(__thumb__)
        __asm__ volatile(".inst 0xe7f001f0");
#else
        __builtin_trap();
#endif

    }

    long long result = 0LL;

    id target = nil;

    if (class_respondsToSelector(class, @selector(forwardingTargetForSelector:))) {
        target = [self forwardingTargetForSelector: _cmd];
    }

    if (target != nil && target != self)
    {
        // Short-circuit machinery was requested. Bail out and restart with the
        // new target.
        return target;
    }
    else
    {
        target = self;
    }

    NSMethodSignature *signature = [target methodSignatureForSelector:_cmd];

    if (signature == nil)
    {
        // DONT EVEN THINK ABOUT REMOVING/HACKING AROUND THIS!
        // EVER!
        // ...
        // yes, I mean YOU!
        [target doesNotRecognizeSelector:_cmd];
        return target;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
    const char *returnType = [signature methodReturnType];

    NSUInteger signatureVerification = 2;
    const char *selName = sel_getName(_cmd);
    for (int i = 0; i < strlen(selName); i++)
    {
        if (selName[i] == ':')
        {
            signatureVerification++;
        }
    }

    NSUInteger signatureArgumentCount = [signature numberOfArguments];
    if (signatureVerification != signatureArgumentCount)
    {
        printf("NSForwardSignatureError: invoked with %d args, but %d expected. Selector %s, class %s\n", signatureVerification, signatureArgumentCount, selName, className);
        RELEASE_LOG("Forward invocation was invoked with %d arguments but claims by signature to respond to %d arguments, break on __NSForwardSignatureError to debug", signatureVerification, signatureArgumentCount);
        // __NSForwardSignatureError();
    }

    for (NSUInteger i = 0; i < MIN(signatureVerification, signatureArgumentCount); i++)
    {
        void *arg = ((const unsigned char *) args->a) + [signature _argInfo: i + 1]->offset;
        [inv setArgument: arg atIndex: i];
    }

    [target forwardInvocation:inv];
#if defined(__arm64__)
    if ([signature _stret])
    {
        returnStorage = indirectResult;
    }
#endif
    [inv getReturnValue:returnStorage];
    return nil;
}

void __block_forwarding__(void* frame) {
    id block = *(id*)frame;
    Class class = object_getClass(block);
    const char *className = class_getName(class);

    if (strncmp(className, ZOMBIE_PREFIX, strlen(ZOMBIE_PREFIX)) == 0) {
        CFLog(3, CFSTR("*** NSBlockInvocation: invocation of deallocated Block instance %p"), block);
        __builtin_trap();
    } else {
        const char* rawSig = _Block_signature(block);

        if (rawSig) {
            NSMethodSignature* sig = [NSMethodSignature signatureWithObjCTypes: rawSig];
            NSBlockInvocation* invocation = [NSBlockInvocation _invocationWithMethodSignature: sig frame: frame];
            invocation.target = nil; // prevent the proxy from accidentally invoking us again
            (((struct NSProxyBlock*)block)->proxy)(invocation);
        } else {
            CFLog(4, CFSTR("*** NSBlockInvocation: Block %p does not have a type signature -- abort"), block);
            __builtin_trap();
        }
    }
};

