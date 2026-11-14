/**
 * Copyright (C) 2017 Lubos Dolezel
 * 
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * Foobar is distributed in the hope that it will be useful,
 * Darling WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
 */

#if !__OBJC2__

#include <objc/runtime.h>
#include <objc/objc-exception.h>
#include "CFLogUtilities.h"
#include "CFInternal.h"
#include "ForFoundationOnly.h"
#include "FoundationExceptions.h"
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>

static void (*__uncaughtExceptionHandler)(id exc) = NULL;

typedef struct {
	jmp_buf buf;
	void* pointers[4];
} LocalData_t;

// QUIRK: a thrown object stays retained while it unwinds to its handler.
// The 32-bit runtime has no hook that retains it, and an autorelease pool
// drained by an @finally block that the exception passes through frees the
// (autoreleased) object before the @catch runs. The 64-bit runtime retains the
// object for the duration of the throw, so the same code works there; a
// 32-bit macOS 10.14 build of the same pattern crashes (black-box observation,
// tier 2), so this is deliberately more tolerant than the original.
// The count is bounded: nothing reports the end of a @catch body, so the
// oldest entries are released when the table is full.
// Test: exception-survives-pool-drain (guest test, i386 and x86_64)
enum { kHeldExceptionCapacity = 16 };

typedef struct {
	id exception;
	size_t depth; // handler stack depth that catches it
} HeldException_t;

typedef struct ThreadChainLink
{
	void** localExceptionData;
	size_t localExceptionDataCount, localExceptionDataSize;
	HeldException_t held[kHeldExceptionCapacity];
	size_t heldCount;
} ThreadChainLink_t;

static int objectIsKindOfNSException(id exc);

static void releaseHeldException(id exc)
{
	if (exc != nil && class_respondsToSelector(object_getClass(exc), @selector(release)))
		[exc release];
}

// Keeps `exc` alive while it propagates to the handler at `depth`, and lets go
// of the exceptions whose catching frame is gone (they target a deeper handler
// than the one now being unwound to).
static void holdExceptionDuringUnwind(ThreadChainLink_t* chainLink, id exc, size_t depth)
{
	size_t kept = 0;
	
	if (exc != nil && class_respondsToSelector(object_getClass(exc), @selector(retain)))
		[exc retain];
	else
		exc = nil;
	
	for (size_t i = 0; i < chainLink->heldCount; i++)
	{
		HeldException_t entry = chainLink->held[i];
		if (entry.depth > depth)
			releaseHeldException(entry.exception);
		else
			chainLink->held[kept++] = entry;
	}
	chainLink->heldCount = kept;
	
	if (exc == nil)
		return;
	
	if (chainLink->heldCount == kHeldExceptionCapacity)
	{
		releaseHeldException(chainLink->held[0].exception);
		memmove(&chainLink->held[0], &chainLink->held[1], sizeof(HeldException_t) * (kHeldExceptionCapacity - 1));
		chainLink->heldCount--;
	}
	chainLink->held[chainLink->heldCount].exception = exc;
	chainLink->held[chainLink->heldCount].depth = depth;
	chainLink->heldCount++;
}

// Throw handler with Foundation support
static void __raiseError(id exc)
{
	ThreadChainLink_t* chainLink = (ThreadChainLink_t*) _CFGetTSD(__CFTSDKeyExceptionData);
	if (chainLink != NULL && chainLink->localExceptionDataCount > 0)
	{
		LocalData_t* led = (LocalData_t*) chainLink->localExceptionData[chainLink->localExceptionDataCount - 1];
		
		if (led != NULL)
		{
			chainLink->localExceptionDataCount--;
			holdExceptionDuringUnwind(chainLink, exc, chainLink->localExceptionDataCount);
			led->pointers[0] = exc;
			_longjmp(led->buf, 1);
		}
	}
	
	if (__uncaughtExceptionHandler != NULL && objectIsKindOfNSException(exc))
	{
		__uncaughtExceptionHandler(exc);
	}
	else
	{
		if (!objectIsKindOfNSException(exc))
		{
			CFLog(kCFLogLevelError, CFSTR("*** Terminating app due to uncaught exception of class %s"), object_getClassName(exc));
		}
		else
		{
			CFLog(kCFLogLevelError, CFSTR("*** Terminating app due to uncaught exception of class %@, reason: \"%@\",\n"
				"*** Call stack:\n%@\n"),
				[exc name], [exc reason], [exc description]);
		}
	}
	abort();
}

static id __exceptionExtract(void* localExceptionData)
{
	LocalData_t* led = (LocalData_t*)localExceptionData;
	return (id) led->pointers[0];
}

static int objectIsKindOfNSException(id exc)
{
	Class c = [NSException class];
	if (class_respondsToSelector(object_getClass(exc), @selector(isKindOfClass:)))
	{
		return [exc isKindOfClass: c];
	}
	else
	{
		// NSException implements isKindOfClass:, so this means it's not an NSException
		return 0;
	}
}

static void __exceptionFinalize(void* ptr)
{
	ThreadChainLink_t* tsd = (ThreadChainLink_t*) ptr;
	for (size_t i = 0; i < tsd->heldCount; i++)
		releaseHeldException(tsd->held[i].exception);
	free(tsd->localExceptionData);
	free(tsd);
}

static int __exceptionMatch(Class matchClass, id exc)
{
	Class excClass = object_getClass(exc);
	
	if (class_respondsToSelector(excClass, @selector(isKindOfClass:)))
	{
		return [exc isKindOfClass: matchClass];
	}
	else
	{
		while (excClass != NULL)
		{
			if (excClass == matchClass)
				return 1;
			excClass = class_getSuperclass(excClass);
		}
		return 0;
	}
}

static void __addHandler2(void* localExceptionData)
{
	ThreadChainLink_t* tsd = (ThreadChainLink_t*) _CFGetTSD(__CFTSDKeyExceptionData);
	
	if (!tsd)
	{
		tsd = (ThreadChainLink_t*) malloc(sizeof(ThreadChainLink_t));
		memset(tsd, 0, sizeof(*tsd));
		_CFSetTSD(__CFTSDKeyExceptionData, tsd, __exceptionFinalize);
	}
	
	if (tsd->localExceptionDataCount+1 > tsd->localExceptionDataSize)
	{
		tsd->localExceptionDataSize += 16;
		tsd->localExceptionData = (void**) realloc(tsd->localExceptionData, sizeof(void*) * tsd->localExceptionDataSize);
	}
	
	// store pointer to localExceptionData in tsd
	tsd->localExceptionData[tsd->localExceptionDataCount] = localExceptionData;
	tsd->localExceptionDataCount++;
}

static void __removeHandler2(void* localExceptionData)
{
	ThreadChainLink_t* tsd = (ThreadChainLink_t*) _CFGetTSD(__CFTSDKeyExceptionData);
	tsd->localExceptionDataCount--;
}

void* _CFDoExceptionOperation(int op, void* arg)
{
	switch (op)
	{
		case kCFDoExceptionOperationGetUncaughtHandler:
			return __uncaughtExceptionHandler;
		case kCFDoExceptionOperationSetUncaughtHandler:
			__uncaughtExceptionHandler = arg;
			break;
		case kCFDoExceptionOperationRaiseError:
			__raiseError((id) arg);
			break;
		case kCFDoExceptionOperationAddHandler:
			__addHandler2(arg);
			break;
		case kCFDoExceptionOperationRemoveHandler:
			__removeHandler2(arg);
			break;
		case kCFDoExceptionOperationExtractException:
			return __exceptionExtract(arg);
	}
	return NULL;
}

static objc_exception_functions_t old_exc_funcs;

// Called from __CFInitialize
void __exceptionInit(void)
{
	objc_exception_functions_t funcs = { 0, __raiseError, __addHandler2, __removeHandler2, __exceptionExtract, __exceptionMatch };
	objc_exception_get_functions(&old_exc_funcs);
	objc_exception_set_functions(&funcs);
}

#endif // !__OBJC2__

