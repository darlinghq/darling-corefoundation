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

// The service side of CFPasteboard: the request handler shared with the in-process store, and the pboard service
// loop (the daemon binary only calls __CFPasteboardRunService).
//
// The service is per user: it is a launchd job of the user's domain and, in addition, refuses any peer whose
// effective uid differs from its own. Every request field is checked for type and size before it is used; the store
// enforces the limits on names, flavors and data again.

#include "CFPasteboardProtocol.h"
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFSet.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFURL.h>
#include <CoreFoundation/CFNumber.h>
#include <Block.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define PROMISE_TIMEOUT_SECONDS 10

static CFStringRef copyStringArg(xpc_object_t request, const char *key, size_t maxBytes) {
	xpc_object_t value = xpc_dictionary_get_value(request, key);
	if (value == NULL || xpc_get_type(value) != XPC_TYPE_STRING) return NULL;
	size_t length = xpc_string_get_length(value);
	if (length == 0 || length > maxBytes) return NULL;
	return CFStringCreateWithBytes(kCFAllocatorSystemDefault, (const UInt8 *)xpc_string_get_string_ptr(value), length, kCFStringEncodingUTF8, false);
}

static bool getUInt(xpc_object_t request, const char *key, uint64_t *out) {
	xpc_object_t value = xpc_dictionary_get_value(request, key);
	if (value == NULL || xpc_get_type(value) != XPC_TYPE_UINT64) return false;
	*out = xpc_uint64_get_value(value);
	return true;
}

static bool getInt(xpc_object_t request, const char *key, int64_t *out) {
	xpc_object_t value = xpc_dictionary_get_value(request, key);
	if (value == NULL || xpc_get_type(value) != XPC_TYPE_INT64) return false;
	*out = xpc_int64_get_value(value);
	return true;
}

static bool getBool(xpc_object_t request, const char *key) {
	xpc_object_t value = xpc_dictionary_get_value(request, key);
	return value != NULL && xpc_get_type(value) == XPC_TYPE_BOOL && xpc_bool_get_value(value);
}

static xpc_object_t statusReply(CFPasteboardStatus status) {
	xpc_object_t reply = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(reply, CFPB_KEY_STATUS, status);
	return reply;
}

// Reads the flavor data of a request into a no-copy CFData; *present tells whether the request carried data at all.
// Returns false if the request is malformed.
static bool getDataArg(xpc_object_t request, CFDataRef *out, bool *present) {
	xpc_object_t value = xpc_dictionary_get_value(request, CFPB_KEY_DATA);
	*out = NULL;
	*present = value != NULL;
	if (value == NULL) return true;
	if (xpc_get_type(value) != XPC_TYPE_DATA) return false;
	size_t length = xpc_data_get_length(value);
	if (length > CFPB_MAX_FLAVOR_DATA) return false;
	*out = CFDataCreateWithBytesNoCopy(kCFAllocatorSystemDefault, length ? xpc_data_get_bytes_ptr(value) : (const UInt8 *)"", (CFIndex)length, kCFAllocatorNull);
	return *out != NULL;
}

static void replyData(CFPBStore *store, CFPBClient client, CFStringRef name, CFPasteboardItemID item, CFStringRef flavor,
		bool resolve, const CFPBServiceHooks *hooks, void (^complete)(xpc_object_t reply)) {
	uint32_t flags = 0;
	CFDataRef data = NULL;
	CFPasteboardStatus status = _CFPBStoreGetFlavor(store, name, item, flavor, &flags, NULL, &data);
	if (status != kCFPasteboardSuccess) {
		complete(statusReply(status));
		return;
	}
	if (data != NULL) {
		xpc_object_t reply = statusReply(kCFPasteboardSuccess);
		xpc_dictionary_set_data(reply, CFPB_KEY_DATA, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
		CFRelease(data);
		complete(reply);
		return;
	}

	// promised
	CFPBClient owner = NULL;
	_CFPBStoreGetInfo(store, name, NULL, NULL, &owner);
	if (!resolve || owner == NULL) {
		complete(statusReply(owner == NULL ? kCFPasteboardNoProvider : kCFPasteboardSuccess));
		return;
	}
	if (owner == client || hooks == NULL || hooks->askOwner == NULL) {
		// the requester made the promise itself: it keeps it, and has to ask its own provider
		xpc_object_t reply = statusReply(kCFPasteboardSuccess);
		xpc_dictionary_set_bool(reply, CFPB_KEY_SELF, true);
		complete(reply);
		return;
	}

	CFRetain(name);
	CFRetain(flavor);
	hooks->askOwner(owner, name, item, flavor, ^(CFPasteboardStatus askStatus) {
		CFDataRef resolved = NULL;
		CFPasteboardStatus got = _CFPBStoreGetFlavor(store, name, item, flavor, NULL, NULL, &resolved);
		if (got == kCFPasteboardSuccess && resolved != NULL) {
			xpc_object_t reply = statusReply(kCFPasteboardSuccess);
			xpc_dictionary_set_data(reply, CFPB_KEY_DATA, CFDataGetBytePtr(resolved), (size_t)CFDataGetLength(resolved));
			complete(reply);
		} else {
			complete(statusReply(got == kCFPasteboardSuccess ? kCFPasteboardNoProvider : got));
		}
		if (resolved != NULL) CFRelease(resolved);
		CFRelease(name);
		CFRelease(flavor);
	});
}

void _CFPBServiceHandle(CFPBStore *store, CFPBClient client, xpc_object_t request, const CFPBServiceHooks *hooks,
		void (^complete)(xpc_object_t reply)) {
	int64_t op;
	if (xpc_get_type(request) != XPC_TYPE_DICTIONARY || !getInt(request, CFPB_KEY_OP, &op) || op < 0 || op >= CFPB_OP_LAST) {
		complete(statusReply(kCFPasteboardInvalid));
		return;
	}

	if (op == CFPB_OP_HELLO) {
		complete(statusReply(kCFPasteboardSuccess));
		return;
	}
	if (op == CFPB_OP_UNIQUE) {
		CFStringRef name = NULL;
		CFPasteboardStatus status = _CFPBStoreCreateUnique(store, client, &name);
		xpc_object_t reply = statusReply(status);
		if (status == kCFPasteboardSuccess) {
			char buffer[CFPB_MAX_NAME_BYTES + 1];
			if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(reply, CFPB_KEY_NAME_RESULT, buffer);
			CFRelease(name);
		}
		complete(reply);
		return;
	}

	CFStringRef name = copyStringArg(request, CFPB_KEY_NAME, CFPB_MAX_NAME_BYTES);
	if (name == NULL) {
		complete(statusReply(kCFPasteboardInvalid));
		return;
	}

	CFStringRef flavor = NULL;
	uint64_t item = 0;
	CFDataRef data = NULL;
	xpc_object_t reply = NULL;
	CFPasteboardStatus status = kCFPasteboardInvalid;
	bool async = false;

	switch (op) {
		case CFPB_OP_OPEN:
			status = _CFPBStoreOpen(store, name);
			reply = statusReply(status);
			break;
		case CFPB_OP_RELEASE:
			status = _CFPBStoreReleaseUnique(store, name, client);
			reply = statusReply(status);
			break;
		case CFPB_OP_BEGIN: {
			uint64_t count = 0;
			CFPBClient previous = NULL;
			status = _CFPBStoreBegin(store, name, client, &count, &previous);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) {
				xpc_dictionary_set_uint64(reply, CFPB_KEY_COUNT, count);
				xpc_dictionary_set_bool(reply, CFPB_KEY_PREVIOUS_SELF, previous == client);
				if (previous != NULL && previous != client && hooks != NULL && hooks->ownerLost != NULL) hooks->ownerLost(previous, name);
				if (hooks != NULL && hooks->changed != NULL) hooks->changed(client, name, count, getBool(request, CFPB_KEY_HOST));
			}
			break;
		}
		case CFPB_OP_INFO: {
			uint64_t count = 0;
			CFIndex items = 0;
			CFPBClient owner = NULL;
			status = _CFPBStoreGetInfo(store, name, &count, &items, &owner);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) {
				CFIndex left = 0;
				_CFPBStorePromisesLeft(store, name, &left);
				xpc_dictionary_set_uint64(reply, CFPB_KEY_COUNT, count);
				xpc_dictionary_set_int64(reply, CFPB_KEY_ITEMS, items);
				xpc_dictionary_set_int64(reply, CFPB_KEY_LEFT, left);
				xpc_dictionary_set_bool(reply, CFPB_KEY_OWNED, owner != NULL && owner == client);
			}
			break;
		}
		case CFPB_OP_ITEM_AT: {
			int64_t index;
			CFPasteboardItemID id = 0;
			if (!getInt(request, CFPB_KEY_INDEX, &index)) break;
			status = _CFPBStoreItemAt(store, name, (CFIndex)index, &id);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) xpc_dictionary_set_uint64(reply, CFPB_KEY_ITEM, id);
			break;
		}
		case CFPB_OP_ADD_ITEM: {
			CFPasteboardItemID id = 0;
			status = _CFPBStoreAddItem(store, name, client, &id);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) {
				xpc_dictionary_set_uint64(reply, CFPB_KEY_ITEM, id);
				uint64_t count = 0;
				if (hooks != NULL && hooks->changed != NULL && _CFPBStoreGetInfo(store, name, &count, NULL, NULL) == kCFPasteboardSuccess) {
					hooks->changed(client, name, count, getBool(request, CFPB_KEY_HOST));
				}
			}
			break;
		}
		case CFPB_OP_FLAVORS: {
			CFArrayRef types = NULL;
			if (!getUInt(request, CFPB_KEY_ITEM, &item)) break;
			status = _CFPBStoreCopyFlavors(store, name, item, &types);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) {
				xpc_object_t array = xpc_array_create(NULL, 0);
				for (CFIndex i = 0; i < CFArrayGetCount(types); ++i) {
					char buffer[CFPB_MAX_FLAVOR_BYTES + 1];
					if (CFStringGetCString(CFArrayGetValueAtIndex(types, i), buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_array_set_string(array, XPC_ARRAY_APPEND, buffer);
				}
				xpc_dictionary_set_value(reply, CFPB_KEY_FLAVORS, array);
				xpc_release(array);
				CFRelease(types);
			}
			break;
		}
		case CFPB_OP_FLAVOR_INFO: {
			uint32_t flags = 0;
			flavor = copyStringArg(request, CFPB_KEY_FLAVOR, CFPB_MAX_FLAVOR_BYTES);
			if (flavor == NULL || !getUInt(request, CFPB_KEY_ITEM, &item)) break;
			Boolean promised = false;
			status = _CFPBStoreGetFlavor(store, name, item, flavor, &flags, &promised, NULL);
			reply = statusReply(status);
			if (status == kCFPasteboardSuccess) {
				xpc_dictionary_set_uint64(reply, CFPB_KEY_FLAGS, flags);
				xpc_dictionary_set_bool(reply, CFPB_KEY_PROMISED, promised);
			}
			break;
		}
		case CFPB_OP_DATA:
			flavor = copyStringArg(request, CFPB_KEY_FLAVOR, CFPB_MAX_FLAVOR_BYTES);
			if (flavor == NULL || !getUInt(request, CFPB_KEY_ITEM, &item)) break;
			replyData(store, client, name, item, flavor, getBool(request, CFPB_KEY_RESOLVE), hooks, complete);
			async = true;
			break;
		case CFPB_OP_SET: {
			uint64_t flags = 0;
			bool present;
			flavor = copyStringArg(request, CFPB_KEY_FLAVOR, CFPB_MAX_FLAVOR_BYTES);
			if (flavor == NULL || !getUInt(request, CFPB_KEY_ITEM, &item) || !getUInt(request, CFPB_KEY_FLAGS, &flags) || flags > UINT32_MAX) break;
			if (!getDataArg(request, &data, &present)) break;
			bool promised = getBool(request, CFPB_KEY_PROMISED);
			Boolean promisesLeft = false;
			uint64_t count = 0;
			status = _CFPBStoreSetFlavor(store, name, client, item, flavor, data, (uint32_t)flags, promised, &count, &promisesLeft);
			reply = statusReply(status);
			xpc_dictionary_set_uint64(reply, CFPB_KEY_COUNT, count);
			xpc_dictionary_set_int64(reply, CFPB_KEY_LEFT, promisesLeft ? 1 : 0);
			if (status == kCFPasteboardSuccess && hooks != NULL && hooks->changed != NULL) hooks->changed(client, name, count, getBool(request, CFPB_KEY_HOST));
			break;
		}
		case CFPB_OP_SUBSCRIBE:
			if (hooks != NULL && hooks->subscribe != NULL) hooks->subscribe(client, name);
			status = kCFPasteboardSuccess;
			reply = statusReply(status);
			break;
		case CFPB_OP_SET_LOCATION: {
			CFStringRef text = copyStringArg(request, CFPB_KEY_LOCATION, 8192);
			if (text == NULL) break;
			CFURLRef url = CFURLCreateWithString(kCFAllocatorSystemDefault, text, NULL);
			CFRelease(text);
			if (url == NULL) break;
			status = _CFPBStoreSetPasteLocation(store, name, url);
			CFRelease(url);
			reply = statusReply(status);
			break;
		}
		case CFPB_OP_GET_LOCATION: {
			CFURLRef url = NULL;
			status = _CFPBStoreCopyPasteLocation(store, name, &url);
			reply = statusReply(status);
			if (url != NULL) {
				CFStringRef text = CFURLGetString(url);
				char buffer[8193];
				if (text != NULL && CFStringGetCString(text, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(reply, CFPB_KEY_LOCATION, buffer);
				CFRelease(url);
			}
			break;
		}
	}

	if (flavor != NULL) CFRelease(flavor);
	if (data != NULL) CFRelease(data);
	CFRelease(name);
	if (!async) complete(reply != NULL ? reply : statusReply(kCFPasteboardInvalid));
}

// ---- the service loop ----

static CFPBStore *serviceStore;
static dispatch_queue_t serviceQueue;
static CFMutableDictionaryRef serviceSubscribers;   // board name -> set of subscribed connections (serviceQueue only)

static void serviceStart(xpc_connection_t listener) {
	static CFPBServiceHooks hooks;
	hooks.askOwner = Block_copy(^(CFPBClient owner, CFStringRef name, CFPasteboardItemID item, CFStringRef flavor, void (^done)(CFPasteboardStatus)) {
		xpc_connection_t ownerConnection = (xpc_connection_t)owner;
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_int64(message, CFPB_KEY_OP, CFPB_OP_PUSH_RESOLVE);
		char buffer[CFPB_MAX_NAME_BYTES + 1];
		if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(message, CFPB_KEY_NAME, buffer);
		if (CFStringGetCString(flavor, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(message, CFPB_KEY_FLAVOR, buffer);
		xpc_dictionary_set_uint64(message, CFPB_KEY_ITEM, item);
		__block bool finished = false;
		void (^finish)(CFPasteboardStatus) = ^(CFPasteboardStatus status) {
			if (!finished) {
				finished = true;
				done(status);
			}
		};
		xpc_connection_send_message_with_reply(ownerConnection, message, serviceQueue, ^(xpc_object_t answer) {
			int64_t status = kCFPasteboardNoProvider;
			if (xpc_get_type(answer) == XPC_TYPE_DICTIONARY) getInt(answer, CFPB_KEY_STATUS, &status);
			finish((CFPasteboardStatus)status);
		});
		xpc_release(message);
		// a stuck or dead owner must not hold a reader up for ever
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, PROMISE_TIMEOUT_SECONDS * NSEC_PER_SEC), serviceQueue, ^{
			finish(kCFPasteboardNoProvider);
		});
	});
	hooks.ownerLost = Block_copy(^(CFPBClient previous, CFStringRef name) {
		xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
		xpc_dictionary_set_int64(message, CFPB_KEY_OP, CFPB_OP_PUSH_OWNER_LOST);
		char buffer[CFPB_MAX_NAME_BYTES + 1];
		if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) xpc_dictionary_set_string(message, CFPB_KEY_NAME, buffer);
		xpc_connection_send_message((xpc_connection_t)previous, message);
		xpc_release(message);
	});

	hooks.subscribe = Block_copy(^(CFPBClient client, CFStringRef name) {
		if (serviceSubscribers == NULL) serviceSubscribers = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFMutableSetRef set = (CFMutableSetRef)CFDictionaryGetValue(serviceSubscribers, name);
		if (set == NULL) {
			set = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, NULL);
			CFDictionarySetValue(serviceSubscribers, name, set);
			CFRelease(set);
		}
		CFSetAddValue(set, client);
	});
	hooks.changed = Block_copy(^(CFPBClient origin, CFStringRef name, uint64_t count, bool host) {
		CFSetRef set = serviceSubscribers ? CFDictionaryGetValue(serviceSubscribers, name) : NULL;
		if (set == NULL) return;
		CFIndex n = CFSetGetCount(set);
		const void **peers = malloc((n ? n : 1) * sizeof(void *));
		if (peers == NULL) return;
		CFSetGetValues(set, peers);
		char buffer[CFPB_MAX_NAME_BYTES + 1];
		if (CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
			for (CFIndex i = 0; i < n; ++i) {
				if (peers[i] == origin) continue;
				xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
				xpc_dictionary_set_int64(message, CFPB_KEY_OP, CFPB_OP_PUSH_CHANGED);
				xpc_dictionary_set_string(message, CFPB_KEY_NAME, buffer);
				xpc_dictionary_set_uint64(message, CFPB_KEY_COUNT, count);
				xpc_dictionary_set_bool(message, CFPB_KEY_HOST, host);
				xpc_connection_send_message((xpc_connection_t)peers[i], message);
				xpc_release(message);
			}
		}
		free(peers);
	});

	xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
		if (xpc_get_type(event) != XPC_TYPE_CONNECTION) return;
		xpc_connection_t peer = event;
		// the service belongs to one user: nobody else may use it
		if (xpc_connection_get_euid(peer) != geteuid()) {
			xpc_connection_cancel(peer);
			return;
		}
		xpc_retain(peer);
		xpc_connection_set_target_queue(peer, serviceQueue);
		xpc_connection_set_event_handler(peer, ^(xpc_object_t message) {
			if (xpc_get_type(message) == XPC_TYPE_DICTIONARY) {
				// the answer may be sent after this handler returned (promises), so the request outlives it
				xpc_retain(message);
				_CFPBServiceHandle(serviceStore, peer, message, &hooks, ^(xpc_object_t result) {
					xpc_object_t answer = xpc_dictionary_create_reply(message);
					if (answer == NULL) {
						xpc_release(result);
						xpc_release(message);
						return;
					}
					xpc_dictionary_apply(result, ^bool(const char *key, xpc_object_t value) {
						xpc_dictionary_set_value(answer, key, value);
						return true;
					});
					xpc_connection_send_message(peer, answer);
					xpc_release(answer);
					xpc_release(result);
					xpc_release(message);
				});
			} else if (message == XPC_ERROR_CONNECTION_INVALID) {
				// the client is gone (the connection is invalid for good after this)
				_CFPBStoreClientGone(serviceStore, peer);
				if (serviceSubscribers != NULL) {
					CFIndex n = CFDictionaryGetCount(serviceSubscribers);
					const void **sets = malloc((n ? n : 1) * sizeof(void *));
					if (sets != NULL) {
						CFDictionaryGetKeysAndValues(serviceSubscribers, NULL, sets);
						for (CFIndex i = 0; i < n; ++i) CFSetRemoveValue((CFMutableSetRef)sets[i], peer);
						free(sets);
					}
				}
				xpc_release(peer);
			}
		});
		xpc_connection_resume(peer);
	});
	xpc_connection_resume(listener);
}

static void serviceSetup(void) {
	serviceQueue = dispatch_queue_create("com.apple.pasteboard.service", DISPATCH_QUEUE_SERIAL);
	// A change count that does not repeat across restarts of the service, so a client's remembered count is never
	// mistaken for a current one.
	serviceStore = _CFPBStoreCreate((uint64_t)time(NULL));
}

void __CFPasteboardRunService(void) {
	serviceSetup();
	xpc_connection_t listener = xpc_connection_create_mach_service(CFPB_SERVICE_NAME, serviceQueue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
	if (listener == NULL) exit(1);
	serviceStart(listener);
	dispatch_main();
}

xpc_endpoint_t __CFPasteboardStartInProcessService(void) {
	serviceSetup();
	xpc_connection_t listener = xpc_connection_create(NULL, serviceQueue);
	serviceStart(listener);
	return xpc_endpoint_create(listener);
}
