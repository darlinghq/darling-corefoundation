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

// Client side of CFPasteboard (see CFPasteboard_Private.h). Every operation is one request to a board store, built
// as a message that the store's handler (CFPasteboardService.c) answers. The store is either the user's pboard
// service, reached over its Mach service, or an in-process store (only when no service answers); which one a
// pasteboard uses is decided when it is created. The promise providers are kept here, in the process that made the promises: the service asks the owner
// to resolve a promise when another process reads it.

#include "CFPasteboardProtocol.h"
#include <CoreFoundation/CFRuntime.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFString.h>
#include <Block.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

const CFStringRef kCFPasteboardGeneral = CFSTR("Apple CFPasteboard general");
const CFStringRef kCFPasteboardFind = CFSTR("Apple CFPasteboard find");
const CFStringRef __kCFPasteboardDrag = CFSTR("Apple CFPasteboard drag");

struct __CFPasteboard {
	CFRuntimeBase _base;
	CFStringRef name;
	Boolean remote;     // the board lives in the service
	Boolean bridged;    // a host bridge mirrors it
};

// ---- the promise provider of this process, per board ----

typedef struct {
	CFPasteboardRef pasteboard;   // retained
	uint64_t changeCount;
	CFPasteboardProviderCallbacks callbacks;
	void *info;
	Boolean allProvidedSent;
} ProviderEntry;

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static CFMutableDictionaryRef gProviders;   // name -> ProviderEntry *
static Boolean gBridgeRegistered;
static CFPasteboardHostBridgeCallbacks gBridge;

// ---- backends ----


static dispatch_once_t gOnce;
static CFPBStore *gLocalStore;
static int gLocalClientToken;
static xpc_connection_t gConnection;
static dispatch_queue_t gQueue;          // events of the connection to the service
static dispatch_queue_t gProviderQueue;  // where providers run on behalf of the service
static int gRemoteState;                 // 0 unknown, 1 reachable, 2 not reachable
static xpc_endpoint_t gEndpoint;         // set by tests: the service to use instead of the Mach service

static void handlePush(xpc_object_t message);
static Boolean nameIsBridged(CFStringRef name);

static void setupOnce(void *unused) {
	gLocalStore = _CFPBStoreCreate(1);
	gQueue = dispatch_queue_create("com.apple.pasteboard.client", DISPATCH_QUEUE_SERIAL);
	gProviderQueue = dispatch_queue_create("com.apple.pasteboard.client.providers", DISPATCH_QUEUE_CONCURRENT);
}

static Boolean remoteAvailable(void) {
	dispatch_once_f(&gOnce, NULL, setupOnce);
	pthread_mutex_lock(&gLock);
	if (gRemoteState == 0) {
		gRemoteState = 2;
		xpc_connection_t connection;
		if (gEndpoint != NULL) {
			connection = xpc_connection_create_from_endpoint(gEndpoint);
			if (connection != NULL) xpc_connection_set_target_queue(connection, gQueue);
		} else {
			connection = xpc_connection_create_mach_service(CFPB_SERVICE_NAME, gQueue, 0);
		}
		if (connection != NULL) {
			xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
				if (xpc_get_type(event) == XPC_TYPE_DICTIONARY) handlePush(event);
			});
			xpc_connection_resume(connection);
			xpc_object_t hello = xpc_dictionary_create(NULL, NULL, 0);
			xpc_dictionary_set_int64(hello, CFPB_KEY_OP, CFPB_OP_HELLO);
			xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, hello);
			xpc_release(hello);
			int64_t status = -1;
			if (xpc_get_type(answer) == XPC_TYPE_DICTIONARY) status = xpc_dictionary_get_int64(answer, CFPB_KEY_STATUS);
			xpc_release(answer);
			if (status == kCFPasteboardSuccess) {
				gConnection = connection;
				gRemoteState = 1;
			} else {
				xpc_connection_cancel(connection);
				xpc_release(connection);
			}
		}
	}
	Boolean available = gRemoteState == 1;
	pthread_mutex_unlock(&gLock);
	return available;
}

// Sends the request to the pasteboard's store and returns the reply (to be released), or NULL if the service does
// not answer. Consumes the request.
static xpc_object_t transact(CFPasteboardRef pasteboard, xpc_object_t request) {
	__block xpc_object_t reply = NULL;
	if (pasteboard->remote) {
		reply = xpc_connection_send_message_with_reply_sync(gConnection, request);
		if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
			// a restarted service answers a repeated request; one retry
			if (reply == XPC_ERROR_CONNECTION_INTERRUPTED) {
				xpc_release(reply);
				reply = xpc_connection_send_message_with_reply_sync(gConnection, request);
			}
			if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
				xpc_release(reply);
				reply = NULL;
			}
		}
	} else {
		_CFPBServiceHandle(gLocalStore, &gLocalClientToken, request, NULL, ^(xpc_object_t result) {
			reply = result;
		});
	}
	xpc_release(request);
	return reply;
}

static xpc_object_t newRequest(int op, CFStringRef name) {
	xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(request, CFPB_KEY_OP, op);
	if (name != NULL) {
		char buffer[CFPB_MAX_NAME_BYTES + 1];
		if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(request, CFPB_KEY_NAME, buffer);
	}
	return request;
}

static void setFlavorArg(xpc_object_t request, CFStringRef flavor) {
	char buffer[CFPB_MAX_FLAVOR_BYTES + 1];
	if (flavor != NULL && CFStringGetCString(flavor, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(request, CFPB_KEY_FLAVOR, buffer);
}

// Performs the request and returns the status, with the reply in *out when the caller wants it
static CFPasteboardStatus perform(CFPasteboardRef pasteboard, xpc_object_t request, xpc_object_t *out) {
	xpc_object_t reply = transact(pasteboard, request);
	if (reply == NULL) return kCFPasteboardUnavailable;
	CFPasteboardStatus status = (CFPasteboardStatus)xpc_dictionary_get_int64(reply, CFPB_KEY_STATUS);
	if (out != NULL) *out = reply; else xpc_release(reply);
	return status;
}

// ---- providers ----

static void providerEntryDrop(ProviderEntry *entry, Boolean notifyOwnerChanged) {
	if (notifyOwnerChanged && entry->callbacks.ownerChanged != NULL) entry->callbacks.ownerChanged(entry->pasteboard, entry->info);
	if (entry->callbacks.release != NULL) entry->callbacks.release(entry->info);
	CFRelease(entry->pasteboard);
	free(entry);
}

// Removes and returns the board's provider entry (NULL if none), optionally only if it is of an older generation
static ProviderEntry *providerEntryTake(CFStringRef name) {
	ProviderEntry *entry = NULL;
	pthread_mutex_lock(&gLock);
	if (gProviders != NULL) {
		entry = (ProviderEntry *)CFDictionaryGetValue(gProviders, name);
		if (entry != NULL) CFDictionaryRemoveValue(gProviders, name);
	}
	pthread_mutex_unlock(&gLock);
	return entry;
}

// Copies the provider of the board, or returns false
static Boolean providerEntryCopy(CFStringRef name, ProviderEntry *copy) {
	Boolean found = false;
	pthread_mutex_lock(&gLock);
	if (gProviders != NULL) {
		ProviderEntry *entry = (ProviderEntry *)CFDictionaryGetValue(gProviders, name);
		if (entry != NULL) {
			*copy = *entry;
			found = true;
		}
	}
	pthread_mutex_unlock(&gLock);
	return found;
}

// A new generation began for the board (here or elsewhere): the promises of the old one are void
static void generationEnded(CFStringRef name) {
	ProviderEntry *entry = providerEntryTake(name);
	if (entry != NULL) providerEntryDrop(entry, true);
}

static void notifyBridge(CFPasteboardRef pasteboard) {
	if (!pasteboard->bridged) return;
	pthread_mutex_lock(&gLock);
	CFPasteboardHostBridgeCallbacks bridge = gBridge;
	pthread_mutex_unlock(&gLock);
	if (bridge.boardChanged != NULL) bridge.boardChanged(pasteboard->name, pasteboard, bridge.info);
}

// Runs on a provider queue: the service asks this process to supply a promised flavor, or tells it its generation ended
static void handlePush(xpc_object_t message) {
	int64_t op = xpc_dictionary_get_int64(message, CFPB_KEY_OP);
	const char *nameText = xpc_dictionary_get_string(message, CFPB_KEY_NAME);
	if ((op != CFPB_OP_PUSH_RESOLVE && op != CFPB_OP_PUSH_OWNER_LOST && op != CFPB_OP_PUSH_CHANGED) || nameText == NULL) {
		xpc_object_t answer = xpc_dictionary_create_reply(message);
		if (answer != NULL) {
			xpc_dictionary_set_int64(answer, CFPB_KEY_STATUS, kCFPasteboardInvalid);
			xpc_connection_send_message(xpc_dictionary_get_remote_connection(message), answer);
			xpc_release(answer);
		}
		return;
	}
	xpc_retain(message);
	dispatch_async(gProviderQueue, ^{
		CFStringRef name = CFStringCreateWithCString(kCFAllocatorSystemDefault, nameText, kCFStringEncodingUTF8);
		if (name == NULL) {
			xpc_release(message);
			return;
		}
		if (op == CFPB_OP_PUSH_OWNER_LOST) {
			generationEnded(name);
		} else if (op == CFPB_OP_PUSH_CHANGED) {
			// another process changed a board this process bridges; imports from the host are not exported back
			if (!xpc_dictionary_get_bool(message, CFPB_KEY_HOST) && nameIsBridged(name)) {
				CFPasteboardRef pasteboard = CFPasteboardCreate(kCFAllocatorSystemDefault, name);
				if (pasteboard != NULL) {
					notifyBridge(pasteboard);
					CFRelease(pasteboard);
				}
			}
		} else {
			CFPasteboardStatus status = kCFPasteboardNoProvider;
			const char *flavorText = xpc_dictionary_get_string(message, CFPB_KEY_FLAVOR);
			ProviderEntry entry;
			if (flavorText != NULL && providerEntryCopy(name, &entry) && entry.callbacks.provide != NULL) {
				CFStringRef flavor = CFStringCreateWithCString(kCFAllocatorSystemDefault, flavorText, kCFStringEncodingUTF8);
				if (flavor != NULL) {
					status = entry.callbacks.provide(entry.pasteboard, xpc_dictionary_get_uint64(message, CFPB_KEY_ITEM), flavor, entry.info);
					CFRelease(flavor);
				}
			}
			xpc_object_t answer = xpc_dictionary_create_reply(message);
			if (answer != NULL) {
				xpc_dictionary_set_int64(answer, CFPB_KEY_STATUS, status);
				xpc_connection_send_message(xpc_dictionary_get_remote_connection(message), answer);
				xpc_release(answer);
			}
		}
		CFRelease(name);
		xpc_release(message);
	});
}

// ---- the object ----

static void __CFPasteboardDeallocate(CFTypeRef cf) {
	CFPasteboardRef pasteboard = (CFPasteboardRef)cf;
	CFRelease(pasteboard->name);
}

static CFTypeID gTypeID = _kCFRuntimeNotATypeID;
static const CFRuntimeClass gClass = {
	0,
	"CFPasteboard",
	NULL,   // init
	NULL,   // copy
	__CFPasteboardDeallocate,
	NULL,
	NULL,
	NULL,
	NULL
};

static void registerClass(void *unused) {
	gTypeID = _CFRuntimeRegisterClass(&gClass);
}

CFTypeID CFPasteboardGetTypeID(void) {
	static dispatch_once_t once;
	dispatch_once_f(&once, NULL, registerClass);
	return gTypeID;
}

static CFPasteboardRef pasteboardAllocate(CFAllocatorRef allocator, CFStringRef name, Boolean remote, Boolean bridged) {
	CFPasteboardRef pasteboard = (CFPasteboardRef)_CFRuntimeCreateInstance(allocator, CFPasteboardGetTypeID(), sizeof(struct __CFPasteboard) - sizeof(CFRuntimeBase), NULL);
	if (pasteboard == NULL) return NULL;
	pasteboard->name = CFStringCreateCopy(kCFAllocatorSystemDefault, name);
	pasteboard->remote = remote;
	pasteboard->bridged = bridged;
	return pasteboard;
}

// Whether a change of the board is the bridge's business: the general and the drag board once a bridge is registered
static Boolean nameIsBridged(CFStringRef name) {
	if (!CFEqual(name, kCFPasteboardGeneral) && !CFEqual(name, __kCFPasteboardDrag)) return false;
	pthread_mutex_lock(&gLock);
	Boolean bridged = gBridgeRegistered;
	pthread_mutex_unlock(&gLock);
	return bridged;
}

CFPasteboardRef CFPasteboardCreate(CFAllocatorRef allocator, CFStringRef name) {
	if (name == NULL || CFGetTypeID(name) != CFStringGetTypeID()) return NULL;
	Boolean bridged = nameIsBridged(name);
	Boolean remote = remoteAvailable();
	CFPasteboardRef pasteboard = pasteboardAllocate(allocator, name, remote, bridged);
	if (pasteboard == NULL) return NULL;
	dispatch_once_f(&gOnce, NULL, setupOnce);
	if (perform(pasteboard, newRequest(CFPB_OP_OPEN, name), NULL) != kCFPasteboardSuccess) {
		CFRelease(pasteboard);
		return NULL;
	}
	// a bridge hears about other processes' changes through the service
	if (bridged && remote) perform(pasteboard, newRequest(CFPB_OP_SUBSCRIBE, name), NULL);
	return pasteboard;
}

CFPasteboardRef CFPasteboardCreateUnique(CFAllocatorRef allocator) {
	Boolean remote = remoteAvailable();
	CFPasteboardRef pasteboard = pasteboardAllocate(allocator, CFSTR(""), remote, false);
	if (pasteboard == NULL) return NULL;
	xpc_object_t reply = NULL;
	if (perform(pasteboard, newRequest(CFPB_OP_UNIQUE, NULL), &reply) != kCFPasteboardSuccess) {
		CFRelease(pasteboard);
		return NULL;
	}
	const char *text = xpc_dictionary_get_string(reply, CFPB_KEY_NAME_RESULT);
	CFStringRef name = text ? CFStringCreateWithCString(kCFAllocatorSystemDefault, text, kCFStringEncodingUTF8) : NULL;
	xpc_release(reply);
	if (name == NULL) {
		CFRelease(pasteboard);
		return NULL;
	}
	CFRelease(pasteboard->name);
	pasteboard->name = name;
	return pasteboard;
}

void CFPasteboardReleaseGlobally(CFPasteboardRef pasteboard) {
	generationEnded(pasteboard->name);
	perform(pasteboard, newRequest(CFPB_OP_RELEASE, pasteboard->name), NULL);
}

CFStringRef CFPasteboardCopyName(CFPasteboardRef pasteboard) {
	return CFRetain(pasteboard->name);
}

CFIndex CFPasteboardGetChangeCount(CFPasteboardRef pasteboard) {
	xpc_object_t reply = NULL;
	if (perform(pasteboard, newRequest(CFPB_OP_INFO, pasteboard->name), &reply) != kCFPasteboardSuccess) return 0;
	CFIndex count = (CFIndex)xpc_dictionary_get_uint64(reply, CFPB_KEY_COUNT);
	xpc_release(reply);
	return count;
}

static CFIndex beginGeneration(CFPasteboardRef pasteboard, Boolean notify, Boolean host) {
	xpc_object_t reply = NULL;
	xpc_object_t request = newRequest(CFPB_OP_BEGIN, pasteboard->name);
	if (host) xpc_dictionary_set_bool(request, CFPB_KEY_HOST, true);
	if (perform(pasteboard, request, &reply) != kCFPasteboardSuccess) return 0;
	CFIndex count = (CFIndex)xpc_dictionary_get_uint64(reply, CFPB_KEY_COUNT);
	xpc_release(reply);
	// whatever this process promised for the board in the earlier generation is void now
	generationEnded(pasteboard->name);
	if (notify) notifyBridge(pasteboard);
	return count;
}

CFIndex CFPasteboardBeginGeneration(CFPasteboardRef pasteboard) {
	return beginGeneration(pasteboard, true, false);
}

CFPasteboardStatus CFPasteboardGetItemCount(CFPasteboardRef pasteboard, CFIndex *count) {
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, newRequest(CFPB_OP_INFO, pasteboard->name), &reply);
	if (status == kCFPasteboardSuccess) {
		*count = (CFIndex)xpc_dictionary_get_int64(reply, CFPB_KEY_ITEMS);
		xpc_release(reply);
	}
	return status;
}

CFPasteboardStatus CFPasteboardGetItemAtIndex(CFPasteboardRef pasteboard, CFIndex index, CFPasteboardItemID *item) {
	xpc_object_t request = newRequest(CFPB_OP_ITEM_AT, pasteboard->name);
	xpc_dictionary_set_int64(request, CFPB_KEY_INDEX, index);
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, request, &reply);
	if (status == kCFPasteboardSuccess) {
		*item = xpc_dictionary_get_uint64(reply, CFPB_KEY_ITEM);
		xpc_release(reply);
	}
	return status;
}

CFPasteboardStatus CFPasteboardAddItem(CFPasteboardRef pasteboard, CFPasteboardItemID *item) {
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, newRequest(CFPB_OP_ADD_ITEM, pasteboard->name), &reply);
	if (status == kCFPasteboardSuccess) {
		*item = xpc_dictionary_get_uint64(reply, CFPB_KEY_ITEM);
		xpc_release(reply);
		notifyBridge(pasteboard);
	}
	return status;
}

CFPasteboardStatus CFPasteboardCopyFlavorsForItem(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFArrayRef *flavors) {
	xpc_object_t request = newRequest(CFPB_OP_FLAVORS, pasteboard->name);
	xpc_dictionary_set_uint64(request, CFPB_KEY_ITEM, item);
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, request, &reply);
	if (status != kCFPasteboardSuccess) return status;
	xpc_object_t array = xpc_dictionary_get_value(reply, CFPB_KEY_FLAVORS);
	CFMutableArrayRef types = CFArrayCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeArrayCallBacks);
	size_t count = array != NULL && xpc_get_type(array) == XPC_TYPE_ARRAY ? xpc_array_get_count(array) : 0;
	for (size_t i = 0; i < count; ++i) {
		const char *text = xpc_array_get_string(array, i);
		CFStringRef type = text ? CFStringCreateWithCString(kCFAllocatorSystemDefault, text, kCFStringEncodingUTF8) : NULL;
		if (type != NULL) {
			CFArrayAppendValue(types, type);
			CFRelease(type);
		}
	}
	xpc_release(reply);
	*flavors = types;
	return kCFPasteboardSuccess;
}

static CFPasteboardStatus flavorInfo(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags *flags, Boolean *promised) {
	xpc_object_t request = newRequest(CFPB_OP_FLAVOR_INFO, pasteboard->name);
	xpc_dictionary_set_uint64(request, CFPB_KEY_ITEM, item);
	setFlavorArg(request, flavor);
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, request, &reply);
	if (status == kCFPasteboardSuccess) {
		if (flags != NULL) *flags = (CFPasteboardFlavorFlags)xpc_dictionary_get_uint64(reply, CFPB_KEY_FLAGS);
		if (promised != NULL) *promised = xpc_dictionary_get_bool(reply, CFPB_KEY_PROMISED);
		xpc_release(reply);
	}
	return status;
}

CFPasteboardStatus CFPasteboardGetDataFlags(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags *flags) {
	return flavorInfo(pasteboard, item, flavor, flags, NULL);
}

Boolean CFPasteboardIsDataPromised(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor) {
	Boolean promised = false;
	return flavorInfo(pasteboard, item, flavor, NULL, &promised) == kCFPasteboardSuccess && promised;
}

// Fires allProvided once, after the last promise of the generation was kept
static void promiseKept(CFPasteboardRef pasteboard, Boolean promisesLeft) {
	if (promisesLeft) return;
	ProviderEntry entry;
	Boolean fire = false;
	pthread_mutex_lock(&gLock);
	ProviderEntry *stored = gProviders ? (ProviderEntry *)CFDictionaryGetValue(gProviders, pasteboard->name) : NULL;
	if (stored != NULL && !stored->allProvidedSent) {
		stored->allProvidedSent = true;
		entry = *stored;
		fire = true;
	}
	pthread_mutex_unlock(&gLock);
	if (fire && entry.callbacks.allProvided != NULL) entry.callbacks.allProvided(entry.pasteboard, entry.info);
}

static CFPasteboardStatus copyData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, Boolean resolve, CFDataRef *data, Boolean *self) {
	xpc_object_t request = newRequest(CFPB_OP_DATA, pasteboard->name);
	xpc_dictionary_set_uint64(request, CFPB_KEY_ITEM, item);
	xpc_dictionary_set_bool(request, CFPB_KEY_RESOLVE, resolve);
	setFlavorArg(request, flavor);
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, request, &reply);
	*data = NULL;
	*self = false;
	if (status != kCFPasteboardSuccess) return status;
	xpc_object_t value = xpc_dictionary_get_value(reply, CFPB_KEY_DATA);
	if (value != NULL && xpc_get_type(value) == XPC_TYPE_DATA) {
		*data = CFDataCreate(kCFAllocatorSystemDefault, xpc_data_get_length(value) ? xpc_data_get_bytes_ptr(value) : (const UInt8 *)"", (CFIndex)xpc_data_get_length(value));
	} else {
		*self = xpc_dictionary_get_bool(reply, CFPB_KEY_SELF);
	}
	xpc_release(reply);
	return kCFPasteboardSuccess;
}

CFPasteboardStatus CFPasteboardCopyData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef *data) {
	Boolean self;
	CFPasteboardStatus status = copyData(pasteboard, item, flavor, true, data, &self);
	if (status != kCFPasteboardSuccess || *data != NULL) return status;
	if (!self) return kCFPasteboardNoProvider;

	// promised by this process: ask the provider here, then read what it stored
	ProviderEntry entry;
	if (!providerEntryCopy(pasteboard->name, &entry) || entry.callbacks.provide == NULL) return kCFPasteboardNoProvider;
	entry.callbacks.provide(entry.pasteboard, item, flavor, entry.info);
	status = copyData(pasteboard, item, flavor, false, data, &self);
	if (status == kCFPasteboardSuccess && *data == NULL) status = kCFPasteboardNoProvider;
	return status;
}

static CFPasteboardStatus setFlavor(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef data, CFPasteboardFlavorFlags flags, Boolean promised, Boolean host, uint64_t *changeCount, Boolean *promisesLeft) {
	xpc_object_t request = newRequest(CFPB_OP_SET, pasteboard->name);
	if (host) xpc_dictionary_set_bool(request, CFPB_KEY_HOST, true);
	xpc_dictionary_set_uint64(request, CFPB_KEY_ITEM, item);
	xpc_dictionary_set_uint64(request, CFPB_KEY_FLAGS, flags);
	xpc_dictionary_set_bool(request, CFPB_KEY_PROMISED, promised);
	setFlavorArg(request, flavor);
	if (data != NULL) xpc_dictionary_set_data(request, CFPB_KEY_DATA, CFDataGetLength(data) ? CFDataGetBytePtr(data) : (const void *)"", (size_t)CFDataGetLength(data));
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, request, &reply);
	if (status == kCFPasteboardSuccess) {
		*changeCount = xpc_dictionary_get_uint64(reply, CFPB_KEY_COUNT);
		*promisesLeft = xpc_dictionary_get_int64(reply, CFPB_KEY_LEFT) != 0;
		xpc_release(reply);
	}
	return status;
}

static CFPasteboardStatus setData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef data, CFPasteboardFlavorFlags flags, Boolean notify, Boolean host) {
	if (data == NULL) data = CFDataCreate(kCFAllocatorSystemDefault, NULL, 0);
	else CFRetain(data);
	uint64_t count = 0;
	Boolean promisesLeft = false;
	CFPasteboardStatus status = setFlavor(pasteboard, item, flavor, data, flags, false, host, &count, &promisesLeft);
	CFRelease(data);
	if (status == kCFPasteboardSuccess) {
		promiseKept(pasteboard, promisesLeft);
		if (notify) notifyBridge(pasteboard);
	}
	return status;
}

CFPasteboardStatus CFPasteboardSetData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef data, CFPasteboardFlavorFlags flags) {
	return setData(pasteboard, item, flavor, data, flags, true, false);
}

static CFPasteboardStatus promiseData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags flags,
		const CFPasteboardProviderCallbacks *provider, void *info, Boolean notify, Boolean host) {
	if (provider == NULL || provider->provide == NULL || provider->version != 0) return kCFPasteboardNoProvider;
	uint64_t count = 0;
	Boolean promisesLeft = false;
	CFPasteboardStatus status = setFlavor(pasteboard, item, flavor, NULL, flags, true, host, &count, &promisesLeft);
	if (status != kCFPasteboardSuccess) return status;

	ProviderEntry *fresh = malloc(sizeof(*fresh));
	if (fresh == NULL) return kCFPasteboardTooLarge;
	fresh->pasteboard = (CFPasteboardRef)CFRetain(pasteboard);
	fresh->changeCount = count;
	fresh->callbacks = *provider;
	fresh->info = info;
	fresh->allProvidedSent = false;

	ProviderEntry *old = NULL;
	pthread_mutex_lock(&gLock);
	if (gProviders == NULL) gProviders = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
	old = (ProviderEntry *)CFDictionaryGetValue(gProviders, pasteboard->name);
	CFDictionarySetValue(gProviders, pasteboard->name, fresh);
	pthread_mutex_unlock(&gLock);
	if (old != NULL) {
		if (old->changeCount == count && old->info == info && old->callbacks.provide == provider->provide) {
			// the same provider promising another flavor: nothing to drop
			CFRelease(old->pasteboard);
			free(old);
		} else {
			// another provider takes over the generation (the replaced one is only released), or the entry is of an
			// older generation that has ended
			providerEntryDrop(old, old->changeCount != count);
		}
	}
	if (notify) notifyBridge(pasteboard);
	return kCFPasteboardSuccess;
}

CFPasteboardStatus CFPasteboardPromiseData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags flags,
		const CFPasteboardProviderCallbacks *provider, void *info) {
	return promiseData(pasteboard, item, flavor, flags, provider, info, true, false);
}

CFPasteboardStatus CFPasteboardResolveAllPromisedData(CFPasteboardRef pasteboard) {
	ProviderEntry entry;
	if (!providerEntryCopy(pasteboard->name, &entry)) return kCFPasteboardSuccess;
	CFIndex items = 0;
	CFPasteboardStatus status = CFPasteboardGetItemCount(pasteboard, &items);
	for (CFIndex i = 0; status == kCFPasteboardSuccess && i < items; ++i) {
		CFPasteboardItemID item;
		CFArrayRef flavors = NULL;
		if (CFPasteboardGetItemAtIndex(pasteboard, i, &item) != kCFPasteboardSuccess || CFPasteboardCopyFlavorsForItem(pasteboard, item, &flavors) != kCFPasteboardSuccess) continue;
		for (CFIndex k = 0; k < CFArrayGetCount(flavors); ++k) {
			CFStringRef flavor = CFArrayGetValueAtIndex(flavors, k);
			if (CFPasteboardIsDataPromised(pasteboard, item, flavor) && entry.callbacks.provide != NULL) {
				entry.callbacks.provide(entry.pasteboard, item, flavor, entry.info);
			}
		}
		CFRelease(flavors);
	}
	return status;
}

CFPasteboardStatus CFPasteboardSetPasteLocation(CFPasteboardRef pasteboard, CFURLRef location) {
	xpc_object_t request = newRequest(CFPB_OP_SET_LOCATION, pasteboard->name);
	char buffer[8193];
	CFStringRef text = location ? CFURLGetString(location) : NULL;
	if (text == NULL || !CFStringGetCString(text, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
		xpc_release(request);
		return kCFPasteboardInvalid;
	}
	xpc_dictionary_set_string(request, CFPB_KEY_LOCATION, buffer);
	return perform(pasteboard, request, NULL);
}

CFPasteboardStatus CFPasteboardCopyPasteLocation(CFPasteboardRef pasteboard, CFURLRef *location) {
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = perform(pasteboard, newRequest(CFPB_OP_GET_LOCATION, pasteboard->name), &reply);
	if (status != kCFPasteboardSuccess) return status;
	const char *text = xpc_dictionary_get_string(reply, CFPB_KEY_LOCATION);
	*location = NULL;
	if (text != NULL) {
		CFStringRef string = CFStringCreateWithCString(kCFAllocatorSystemDefault, text, kCFStringEncodingUTF8);
		if (string != NULL) {
			*location = CFURLCreateWithString(kCFAllocatorSystemDefault, string, NULL);
			CFRelease(string);
		}
	}
	xpc_release(reply);
	return kCFPasteboardSuccess;
}

// ---- host bridge ----

Boolean CFPasteboardRegisterHostBridge(const CFPasteboardHostBridgeCallbacks *callbacks) {
	if (callbacks == NULL || callbacks->version != 0) return false;
	Boolean registered = false;
	pthread_mutex_lock(&gLock);
	if (!gBridgeRegistered) {
		gBridge = *callbacks;
		gBridgeRegistered = true;
		registered = true;
	}
	pthread_mutex_unlock(&gLock);
	return registered;
}

static CFPasteboardStatus bridgeProvide(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, void *info) {
	pthread_mutex_lock(&gLock);
	CFPasteboardHostBridgeCallbacks bridge = gBridge;
	pthread_mutex_unlock(&gLock);
	if (bridge.copyData == NULL) return kCFPasteboardNoProvider;
	// the item's position is its identifier minus the first one handed out by ReplaceContents
	CFDataRef data = bridge.copyData(pasteboard->name, (CFIndex)(item - 1), flavor, bridge.info);
	if (data == NULL) return kCFPasteboardNoProvider;
	CFPasteboardStatus status = setData(pasteboard, item, flavor, data, kCFPasteboardFlavorNoFlags, false, true);
	CFRelease(data);
	return status;
}

CFIndex CFPasteboardHostBridgeReplaceContents(CFStringRef name, CFArrayRef items) {
	if (name == NULL || items == NULL || !nameIsBridged(name)) return 0;
	CFPasteboardRef pasteboard = CFPasteboardCreate(kCFAllocatorSystemDefault, name);
	if (pasteboard == NULL) return 0;
	CFIndex count = beginGeneration(pasteboard, false, true);
	static const CFPasteboardProviderCallbacks provider = { 0, bridgeProvide, NULL, NULL, NULL };
	for (CFIndex i = 0; count != 0 && i < CFArrayGetCount(items); ++i) {
		CFDictionaryRef flavors = CFArrayGetValueAtIndex(items, i);
		if (CFGetTypeID(flavors) != CFDictionaryGetTypeID()) continue;
		CFIndex flavorCount = CFDictionaryGetCount(flavors);
		const void **keys = malloc((flavorCount ? flavorCount : 1) * sizeof(void *));
		const void **values = malloc((flavorCount ? flavorCount : 1) * sizeof(void *));
		if (keys != NULL && values != NULL) {
			CFDictionaryGetKeysAndValues(flavors, keys, values);
			for (CFIndex k = 0; k < flavorCount; ++k) {
				if (CFGetTypeID(keys[k]) != CFStringGetTypeID()) continue;
				// items of a replaced board are numbered from 1 in array order so that a lazy flavor can be
				// mapped back to its position
				if (values[k] == kCFNull) promiseData(pasteboard, (CFPasteboardItemID)(i + 1), keys[k], kCFPasteboardFlavorNoFlags, &provider, NULL, false, true);
				else if (CFGetTypeID(values[k]) == CFDataGetTypeID()) setData(pasteboard, (CFPasteboardItemID)(i + 1), keys[k], values[k], kCFPasteboardFlavorNoFlags, false, true);
			}
		}
		free(keys);
		free(values);
	}
	CFRelease(pasteboard);
	return count;
}

void __CFPasteboardAdoptServiceEndpoint(xpc_endpoint_t endpoint) {
	pthread_mutex_lock(&gLock);
	if (gEndpoint == NULL && gRemoteState == 0) gEndpoint = xpc_retain(endpoint);
	pthread_mutex_unlock(&gLock);
}
