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

// The distributed notification center: notifications posted to CFNotificationCenterGetDistributedCenter() reach the
// matching observers of every process of the container, through the distributed notification daemon (see
// CFDistributedNotification_Private.h). If the daemon cannot be reached, the center delivers within the process only.
//
// Delivery follows what macOS does for a plain process: callbacks run on the main thread's run loop whichever thread
// added the observer, a posting process receives its own notifications, and the userInfo must be a property list.

#include "CFDistributedNotificationInternal.h"
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFPropertyList.h>
#include <CoreFoundation/CFRunLoop.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFPriv.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <xpc/xpc.h>

typedef struct {
	int64_t id;
	const void *observer;
	CFNotificationCallback callBack;
	CFStringRef name;     // retained, or NULL for any
	CFStringRef object;   // retained, or NULL for any
	CFNotificationSuspensionBehavior behavior;
} DistributedObserver;

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static CFMutableArrayRef gObservers;     // DistributedObserver *
static int64_t gNextID = 1;
static Boolean gSuspended;
static int gState;                       // 0 not tried, 1 daemon reachable, 2 not reachable
static xpc_connection_t gConnection;
static dispatch_queue_t gQueue;
static dispatch_once_t gOnce;

static CFNotificationCenterRef centerRef(void) { return CFNotificationCenterGetDistributedCenter(); }

static void freeObserver(DistributedObserver *o) {
	if (o->name != NULL) CFRelease(o->name);
	if (o->object != NULL) CFRelease(o->object);
	free(o);
}

static void setupOnce(void *unused) {
	gObservers = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	gQueue = dispatch_queue_create("com.apple.distributed_notifications.client", DISPATCH_QUEUE_SERIAL);
}

static Boolean stringsEqual(CFStringRef a, CFStringRef b) {
	return CFStringCompare(a, b, 0) == kCFCompareEqualTo;
}

static void setString(xpc_object_t message, const char *key, CFStringRef s) {
	char buffer[CFDN_MAX_STRING];
	if (s != NULL && CFStringGetCString(s, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(message, key, buffer);
}

static CFStringRef copyString(xpc_object_t message, const char *key) {
	const char *text = xpc_dictionary_get_string(message, key);
	return text != NULL ? CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8) : NULL;
}

// Runs the callbacks of the observers with the given ids, on the main run loop.
static void deliverLocally(CFArrayRef ids, CFStringRef name, CFStringRef object, CFDictionaryRef userInfo) {
	CFRetain(ids);
	CFRetain(name);
	if (object != NULL) CFRetain(object);
	if (userInfo != NULL) CFRetain(userInfo);
	CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
		CFIndex count = CFArrayGetCount(ids);
		for (CFIndex i = 0; i < count; i++) {
			int64_t id = 0;
			CFNumberGetValue(CFArrayGetValueAtIndex(ids, i), kCFNumberSInt64Type, &id);
			DistributedObserver copy;
			Boolean found = false;
			pthread_mutex_lock(&gLock);
			CFIndex n = CFArrayGetCount(gObservers);
			for (CFIndex j = 0; j < n; j++) {
				DistributedObserver *o = (DistributedObserver *)CFArrayGetValueAtIndex(gObservers, j);
				if (o->id == id) { copy = *o; found = true; break; }
			}
			pthread_mutex_unlock(&gLock);
			if (found) copy.callBack(centerRef(), (void *)copy.observer, name, object, userInfo);
		}
		CFRelease(ids);
		CFRelease(name);
		if (object != NULL) CFRelease(object);
		if (userInfo != NULL) CFRelease(userInfo);
	});
	CFRunLoopWakeUp(CFRunLoopGetMain());
}

static void handleDeliver(xpc_object_t message) {
	xpc_object_t idArray = xpc_dictionary_get_value(message, CFDN_KEY_IDS);
	CFStringRef name = copyString(message, CFDN_KEY_NAME);
	if (idArray == NULL || xpc_get_type(idArray) != XPC_TYPE_ARRAY || name == NULL) {
		if (name != NULL) CFRelease(name);
		return;
	}
	CFMutableArrayRef ids = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	for (size_t i = 0; i < xpc_array_get_count(idArray); i++) {
		int64_t id = xpc_array_get_int64(idArray, i);
		CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &id);
		CFArrayAppendValue(ids, number);
		CFRelease(number);
	}
	CFStringRef object = copyString(message, CFDN_KEY_OBJECT);
	CFDictionaryRef userInfo = NULL;
	size_t length = 0;
	const void *bytes = xpc_dictionary_get_data(message, CFDN_KEY_USERINFO, &length);
	if (bytes != NULL && length > 0) {
		CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
		CFPropertyListRef plist = CFPropertyListCreateWithData(kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, NULL);
		CFRelease(data);
		if (plist != NULL && CFGetTypeID(plist) == CFDictionaryGetTypeID()) userInfo = plist;
		else if (plist != NULL) CFRelease(plist);
	}
	deliverLocally(ids, name, object, userInfo);
	CFRelease(ids);
	CFRelease(name);
	if (object != NULL) CFRelease(object);
	if (userInfo != NULL) CFRelease(userInfo);
}

static void sendAdd(xpc_connection_t connection, DistributedObserver *o) {
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, CFDN_KEY_OP, CFDN_OP_ADD);
	xpc_dictionary_set_int64(message, CFDN_KEY_ID, o->id);
	xpc_dictionary_set_int64(message, CFDN_KEY_BEHAVIOR, o->behavior);
	setString(message, CFDN_KEY_NAME, o->name);
	setString(message, CFDN_KEY_OBJECT, o->object);
	xpc_connection_send_message(connection, message);
	xpc_release(message);
}

// After the daemon was restarted its state is gone: register everything again.
static void resubscribe(xpc_connection_t connection) {
	pthread_mutex_lock(&gLock);
	CFIndex count = CFArrayGetCount(gObservers);
	for (CFIndex i = 0; i < count; i++) sendAdd(connection, (DistributedObserver *)CFArrayGetValueAtIndex(gObservers, i));
	if (gSuspended) {
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_int64(message, CFDN_KEY_OP, CFDN_OP_SUSPEND);
		xpc_dictionary_set_bool(message, CFDN_KEY_SUSPENDED, true);
		xpc_connection_send_message(connection, message);
		xpc_release(message);
	}
	pthread_mutex_unlock(&gLock);
}

// The connection to the daemon, or NULL when it is not there. Decided once per process.
static xpc_connection_t connection(void) {
	dispatch_once_f(&gOnce, NULL, setupOnce);
	pthread_mutex_lock(&gLock);
	if (gState == 0) {
		gState = 2;
		xpc_connection_t c = xpc_connection_create_mach_service(CFDN_SERVICE_NAME, gQueue, 0);
		if (c != NULL) {
			xpc_connection_set_event_handler(c, ^(xpc_object_t event) {
				if (xpc_get_type(event) == XPC_TYPE_DICTIONARY) {
					if (xpc_dictionary_get_int64(event, CFDN_KEY_OP) == CFDN_OP_DELIVER) handleDeliver(event);
				} else if (event == XPC_ERROR_CONNECTION_INTERRUPTED) {
					resubscribe(gConnection);
				}
			});
			xpc_connection_resume(c);
			xpc_object_t hello = xpc_dictionary_create(NULL, NULL, 0);
			xpc_dictionary_set_int64(hello, CFDN_KEY_OP, CFDN_OP_HELLO);
			xpc_object_t reply = xpc_connection_send_message_with_reply_sync(c, hello);
			xpc_release(hello);
			if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY) {
				gConnection = c;
				gState = 1;
			} else {
				xpc_connection_cancel(c);
				xpc_release(c);
			}
			xpc_release(reply);
		}
	}
	xpc_connection_t c = gState == 1 ? gConnection : NULL;
	pthread_mutex_unlock(&gLock);
	return c;
}

void _CFDistributedAddObserver(const void *observer, CFNotificationCallback callBack, CFStringRef name,
                               CFStringRef object, CFNotificationSuspensionBehavior behavior) {
	if (callBack == NULL) return;
	xpc_connection_t c = connection();
	DistributedObserver *o = calloc(1, sizeof(*o));
	o->observer = observer;
	o->callBack = callBack;
	o->name = name != NULL ? CFStringCreateCopy(kCFAllocatorDefault, name) : NULL;
	o->object = object != NULL ? CFStringCreateCopy(kCFAllocatorDefault, object) : NULL;
	o->behavior = behavior;
	pthread_mutex_lock(&gLock);
	o->id = gNextID++;
	CFArrayAppendValue(gObservers, o);
	pthread_mutex_unlock(&gLock);
	if (c != NULL) sendAdd(c, o);
}

static Boolean observerMatches(const DistributedObserver *o, const void *observer, CFStringRef name, CFStringRef object) {
	if (o->observer != observer) return false;
	if (name != NULL && (o->name == NULL || !stringsEqual(o->name, name))) return false;
	if (object != NULL && (o->object == NULL || !stringsEqual(o->object, object))) return false;
	return true;
}

void _CFDistributedRemoveObserver(const void *observer, CFStringRef name, CFStringRef object) {
	xpc_connection_t c = connection();
	pthread_mutex_lock(&gLock);
	for (CFIndex i = CFArrayGetCount(gObservers) - 1; i >= 0; i--) {
		DistributedObserver *o = (DistributedObserver *)CFArrayGetValueAtIndex(gObservers, i);
		if (!observerMatches(o, observer, name, object)) continue;
		if (c != NULL) {
			xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
			xpc_dictionary_set_int64(message, CFDN_KEY_OP, CFDN_OP_REMOVE);
			xpc_dictionary_set_int64(message, CFDN_KEY_ID, o->id);
			xpc_connection_send_message(c, message);
			xpc_release(message);
		}
		CFArrayRemoveValueAtIndex(gObservers, i);
		freeObserver(o);
	}
	pthread_mutex_unlock(&gLock);
}

void _CFDistributedSetSuspended(Boolean suspended) {
	xpc_connection_t c = connection();
	pthread_mutex_lock(&gLock);
	gSuspended = suspended;
	pthread_mutex_unlock(&gLock);
	if (c != NULL) {
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_int64(message, CFDN_KEY_OP, CFDN_OP_SUSPEND);
		xpc_dictionary_set_bool(message, CFDN_KEY_SUSPENDED, suspended);
		xpc_connection_send_message(c, message);
		xpc_release(message);
	}
}

Boolean _CFDistributedIsSuspended(void) {
	pthread_mutex_lock(&gLock);
	Boolean suspended = gSuspended;
	pthread_mutex_unlock(&gLock);
	return suspended;
}

// Without the daemon: the same matching and suspension rules, for this process's observers only.
static void postLocally(CFStringRef name, CFStringRef object, CFDictionaryRef userInfo, Boolean immediate) {
	CFMutableArrayRef ids = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	pthread_mutex_lock(&gLock);
	for (CFIndex i = 0; i < CFArrayGetCount(gObservers); i++) {
		DistributedObserver *o = (DistributedObserver *)CFArrayGetValueAtIndex(gObservers, i);
		if (o->name != NULL && !stringsEqual(o->name, name)) continue;
		if (o->object != NULL && (object == NULL || !stringsEqual(o->object, object))) continue;
		if (!CFDN_ShouldDeliver(gSuspended, immediate, o->behavior)) continue;
		CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &o->id);
		CFArrayAppendValue(ids, number);
		CFRelease(number);
	}
	pthread_mutex_unlock(&gLock);
	if (CFArrayGetCount(ids) > 0) deliverLocally(ids, name, object, userInfo);
	CFRelease(ids);
}

void _CFDistributedPost(CFStringRef name, CFStringRef object, CFDictionaryRef userInfo, Boolean immediate) {
	if (name == NULL) return;
	if (object != NULL && CFGetTypeID(object) != CFStringGetTypeID()) return;
	CFDataRef data = NULL;
	if (userInfo != NULL) {
		// Only property list values are carried between processes; a notification with anything else is not sent.
		if (!CFPropertyListIsValid(userInfo, kCFPropertyListBinaryFormat_v1_0)) return;
		data = CFPropertyListCreateData(kCFAllocatorDefault, userInfo, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
		if (data == NULL || CFDataGetLength(data) > CFDN_MAX_USERINFO) {
			if (data != NULL) CFRelease(data);
			return;
		}
	}
	xpc_connection_t c = connection();
	if (c == NULL) {
		postLocally(name, object, userInfo, immediate);
	} else {
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_int64(message, CFDN_KEY_OP, CFDN_OP_POST);
		xpc_dictionary_set_bool(message, CFDN_KEY_IMMEDIATE, immediate);
		setString(message, CFDN_KEY_NAME, name);
		setString(message, CFDN_KEY_OBJECT, object);
		if (data != NULL) xpc_dictionary_set_data(message, CFDN_KEY_USERINFO, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
		xpc_connection_send_message(c, message);
		xpc_release(message);
	}
	if (data != NULL) CFRelease(data);
}
