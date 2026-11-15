/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The CFPasteboard store: boards, change counts, items and flavors, ownership of a generation, promises with a
 * provider, unique boards, the paste location and the host bridge hook. Everything uses boards that no other process
 * knows (unique boards) so it behaves the same whether the boards live in the pboard service or in the process.
 * The last part registers a host bridge for the process and works on the general board.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPasteboard_Private.h>
#include "CFPasteboardProtocol.h"   // the service's messages (private; build with -I<corefoundation source dir>)
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static CFDataRef bytes(const char *text) {
	return CFDataCreate(NULL, (const UInt8 *)text, (CFIndex)strlen(text));
}

static Boolean dataEquals(CFDataRef data, const char *text) {
	return data != NULL && CFDataGetLength(data) == (CFIndex)strlen(text) && memcmp(CFDataGetBytePtr(data), text, strlen(text)) == 0;
}

static CFStringRef const kText = CFSTR("public.utf8-plain-text");
static CFStringRef const kHTML = CFSTR("public.html");
static CFStringRef const kPNG = CFSTR("public.png");

// ---- a provider that records what happens to it ----
static int provided, allProvided, ownerChanged, released;
static CFPasteboardStatus provide(CFPasteboardRef pb, CFPasteboardItemID item, CFStringRef flavor, void *info) {
	provided++;
	CFDataRef data = bytes(info);
	CFPasteboardStatus status = CFPasteboardSetData(pb, item, flavor, data, kCFPasteboardFlavorNoFlags);
	CFRelease(data);
	return status;
}
static void onAllProvided(CFPasteboardRef pb, void *info) { allProvided++; }
static void onOwnerChanged(CFPasteboardRef pb, void *info) { ownerChanged++; }
static void onRelease(void *info) { released++; }
static const CFPasteboardProviderCallbacks provider = { 0, provide, onAllProvided, onOwnerChanged, onRelease };

static void testBasics(void) {
	CFPasteboardRef a = CFPasteboardCreateUnique(NULL), b = CFPasteboardCreateUnique(NULL);
	CHECK(a != NULL && b != NULL);
	CFStringRef an = CFPasteboardCopyName(a), bn = CFPasteboardCopyName(b);
	CHECK(!CFEqual(an, bn));
	CHECK(CFStringHasPrefix(an, CFSTR("CFPasteboardUnique-")) && CFStringGetLength(an) == 31);
	CHECK(CFGetTypeID(a) == CFPasteboardGetTypeID());

	// a board has no contents and no owner until a generation begins
	CFIndex count = -1;
	CHECK(CFPasteboardGetItemCount(a, &count) == kCFPasteboardSuccess && count == 0);
	CHECK(CFPasteboardSetData(a, 1, kText, NULL, 0) == kCFPasteboardNotOwner);

	CFIndex c0 = CFPasteboardGetChangeCount(a);
	CHECK(c0 > 0);
	CFIndex c1 = CFPasteboardBeginGeneration(a);
	CHECK(c1 == c0 + 1 && CFPasteboardGetChangeCount(a) == c1);
	CHECK(CFPasteboardGetChangeCount(b) == CFPasteboardGetChangeCount(b));   // boards are independent

	CFPasteboardItemID item = 0;
	CHECK(CFPasteboardAddItem(a, &item) == kCFPasteboardSuccess);
	CFDataRef hello = bytes("hello"), page = bytes("<b>x</b>");
	CHECK(CFPasteboardSetData(a, item, kText, hello, kCFPasteboardFlavorNoFlags) == kCFPasteboardSuccess);
	CHECK(CFPasteboardSetData(a, item, kHTML, page, kCFPasteboardFlavorSenderOnly | kCFPasteboardFlavorNotSaved) == kCFPasteboardSuccess);
	CHECK(CFPasteboardGetChangeCount(a) == c1);   // adding flavors does not change the count

	CHECK(CFPasteboardGetItemCount(a, &count) == kCFPasteboardSuccess && count == 1);
	CFPasteboardItemID again = 0;
	CHECK(CFPasteboardGetItemAtIndex(a, 0, &again) == kCFPasteboardSuccess && again == item);
	CHECK(CFPasteboardGetItemAtIndex(a, 1, &again) == kCFPasteboardBadIndex);
	CHECK(CFPasteboardGetItemAtIndex(a, -1, &again) == kCFPasteboardBadIndex);

	CFArrayRef flavors = NULL;
	CHECK(CFPasteboardCopyFlavorsForItem(a, item, &flavors) == kCFPasteboardSuccess && CFArrayGetCount(flavors) == 2);
	CHECK(CFEqual(CFArrayGetValueAtIndex(flavors, 0), kText) && CFEqual(CFArrayGetValueAtIndex(flavors, 1), kHTML));
	CFRelease(flavors);
	CHECK(CFPasteboardCopyFlavorsForItem(a, item + 77, &flavors) == kCFPasteboardBadItem);

	CFDataRef data = NULL;
	CHECK(CFPasteboardCopyData(a, item, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "hello"));
	CFRelease(data);
	CHECK(CFPasteboardCopyData(a, item, kPNG, &data) == kCFPasteboardBadFlavor);
	CHECK(CFPasteboardCopyData(a, item + 77, kText, &data) == kCFPasteboardBadItem);

	CFPasteboardFlavorFlags flags = 0;
	CHECK(CFPasteboardGetDataFlags(a, item, kHTML, &flags) == kCFPasteboardSuccess && flags == (kCFPasteboardFlavorSenderOnly | kCFPasteboardFlavorNotSaved));
	CHECK(CFPasteboardGetDataFlags(a, item, kText, &flags) == kCFPasteboardSuccess && flags == 0);
	CHECK(!CFPasteboardIsDataPromised(a, item, kText));

	// setting a flavor again replaces it, in place
	CFDataRef replacement = bytes("bye");
	CHECK(CFPasteboardSetData(a, item, kText, replacement, kCFPasteboardFlavorNoFlags) == kCFPasteboardSuccess);
	CHECK(CFPasteboardCopyData(a, item, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "bye"));
	CFRelease(data);
	CHECK(CFPasteboardCopyFlavorsForItem(a, item, &flavors) == kCFPasteboardSuccess && CFArrayGetCount(flavors) == 2 && CFEqual(CFArrayGetValueAtIndex(flavors, 0), kText));
	CFRelease(flavors);

	// empty data is data
	CHECK(CFPasteboardSetData(a, item, kPNG, NULL, 0) == kCFPasteboardSuccess);
	CHECK(CFPasteboardCopyData(a, item, kPNG, &data) == kCFPasteboardSuccess && CFDataGetLength(data) == 0);
	CFRelease(data);

	// a caller-chosen identifier creates the item
	CHECK(CFPasteboardSetData(a, 5, kText, hello, 0) == kCFPasteboardSuccess);
	CHECK(CFPasteboardGetItemCount(a, &count) == kCFPasteboardSuccess && count == 2);
	CFPasteboardItemID second = 0;
	CHECK(CFPasteboardAddItem(a, &second) == kCFPasteboardSuccess && second != item && second != 5);

	// another reference to the same board sees the same contents
	CFPasteboardRef same = CFPasteboardCreate(NULL, an);
	CHECK(same != NULL && CFPasteboardGetChangeCount(same) == c1);
	CHECK(CFPasteboardCopyData(same, item, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "bye"));
	CFRelease(data);
	CFRelease(same);

	// the other board was not touched
	CHECK(CFPasteboardGetItemCount(b, &count) == kCFPasteboardSuccess && count == 0);

	// a new generation drops everything
	CHECK(CFPasteboardBeginGeneration(a) == c1 + 1);
	CHECK(CFPasteboardGetItemCount(a, &count) == kCFPasteboardSuccess && count == 0);
	CHECK(CFPasteboardCopyData(a, item, kText, &data) == kCFPasteboardBadItem);

	CFRelease(hello); CFRelease(page); CFRelease(replacement);
	CFPasteboardReleaseGlobally(a);
	CFPasteboardReleaseGlobally(b);
	CFRelease(a); CFRelease(b); CFRelease(an); CFRelease(bn);
}

static void testInvalid(void) {
	CHECK(CFPasteboardCreate(NULL, NULL) == NULL);
	CHECK(CFPasteboardCreate(NULL, CFSTR("")) == NULL);
	char longName[300];
	memset(longName, 'a', sizeof(longName) - 1);
	longName[sizeof(longName) - 1] = 0;
	CFStringRef tooLong = CFStringCreateWithCString(NULL, longName, kCFStringEncodingASCII);
	CHECK(CFPasteboardCreate(NULL, tooLong) == NULL);
	CFRelease(tooLong);

	CFPasteboardRef pb = CFPasteboardCreateUnique(NULL);
	CFPasteboardBeginGeneration(pb);
	CFStringRef longFlavor = CFStringCreateWithCString(NULL, longName, kCFStringEncodingASCII);
	CHECK(CFPasteboardSetData(pb, 1, longFlavor, NULL, 0) == kCFPasteboardInvalid);
	CHECK(CFPasteboardSetData(pb, 1, CFSTR(""), NULL, 0) == kCFPasteboardInvalid);
	CFRelease(longFlavor);
	// the Promised bit is the store's to set
	CFDataRef data = bytes("x");
	CHECK(CFPasteboardSetData(pb, 1, kText, data, kCFPasteboardFlavorPromised) == kCFPasteboardSuccess);
	CHECK(!CFPasteboardIsDataPromised(pb, 1, kText));
	CFRelease(data);
	CFPasteboardReleaseGlobally(pb);
	CFRelease(pb);
}

static void testPromises(void) {
	CFPasteboardRef pb = CFPasteboardCreateUnique(NULL);
	provided = allProvided = ownerChanged = released = 0;
	CFPasteboardBeginGeneration(pb);
	CFPasteboardItemID item = 0;
	CHECK(CFPasteboardAddItem(pb, &item) == kCFPasteboardSuccess);
	CFDataRef plain = bytes("plain");
	CHECK(CFPasteboardSetData(pb, item, kHTML, plain, 0) == kCFPasteboardSuccess);
	// a promise made visible reads as flagged Promised (the Pasteboard Manager's), one made without it reads as made
	// (NSPasteboard's); both are promised as far as CFPasteboardIsDataPromised goes
	CHECK(CFPasteboardPromiseData(pb, item, kText, kCFPasteboardFlavorPromiseVisible, &provider, "lazy text") == kCFPasteboardSuccess);
	CHECK(CFPasteboardPromiseData(pb, item, kPNG, kCFPasteboardFlavorSenderOnly, &provider, "lazy text") == kCFPasteboardSuccess);
	CHECK(CFPasteboardPromiseData(pb, item, kText, 0, NULL, NULL) == kCFPasteboardNoProvider);

	CHECK(provided == 0 && released == 0);
	CHECK(CFPasteboardIsDataPromised(pb, item, kText) && !CFPasteboardIsDataPromised(pb, item, kHTML));
	CFPasteboardFlavorFlags flags = 0;
	CHECK(CFPasteboardGetDataFlags(pb, item, kPNG, &flags) == kCFPasteboardSuccess && flags == kCFPasteboardFlavorSenderOnly);
	CHECK(CFPasteboardGetDataFlags(pb, item, kText, &flags) == kCFPasteboardSuccess && flags == kCFPasteboardFlavorPromised);
	CHECK(CFPasteboardIsDataPromised(pb, item, kPNG));

	CFDataRef data = NULL;
	CHECK(CFPasteboardCopyData(pb, item, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "lazy text"));
	CFRelease(data);
	CHECK(provided == 1 && allProvided == 0);   // the png promise is still open
	CHECK(!CFPasteboardIsDataPromised(pb, item, kText));
	CHECK(CFPasteboardGetDataFlags(pb, item, kText, &flags) == kCFPasteboardSuccess && flags == 0);
	CHECK(CFPasteboardCopyData(pb, item, kText, &data) == kCFPasteboardSuccess);   // not asked again
	CFRelease(data);
	CHECK(provided == 1);

	CHECK(CFPasteboardResolveAllPromisedData(pb) == kCFPasteboardSuccess);
	CHECK(provided == 2 && allProvided == 1 && !CFPasteboardIsDataPromised(pb, item, kPNG));
	CHECK(ownerChanged == 0 && released == 0);

	// a new generation ends the provider's registration
	CFPasteboardBeginGeneration(pb);
	CHECK(ownerChanged == 1 && released == 1);

	// a promise needs a provider that can supply data
	static const CFPasteboardProviderCallbacks lazy = { 0, NULL, NULL, NULL, NULL };
	CFPasteboardAddItem(pb, &item);
	CHECK(CFPasteboardPromiseData(pb, item, kText, 0, &lazy, NULL) == kCFPasteboardNoProvider);

	// promises of an abandoned generation are gone
	provided = 0;
	CFPasteboardBeginGeneration(pb);
	CFPasteboardAddItem(pb, &item);
	CHECK(CFPasteboardPromiseData(pb, item, kText, 0, &provider, "again") == kCFPasteboardSuccess);
	CFPasteboardBeginGeneration(pb);
	CHECK(CFPasteboardCopyData(pb, item, kText, &data) == kCFPasteboardBadItem);
	CHECK(provided == 0);
	CFRelease(plain);
	CFPasteboardReleaseGlobally(pb);
	CFRelease(pb);
}

static void testPasteLocation(void) {
	CFPasteboardRef pb = CFPasteboardCreateUnique(NULL);
	CFPasteboardBeginGeneration(pb);
	CFURLRef url = NULL;
	CHECK(CFPasteboardCopyPasteLocation(pb, &url) == kCFPasteboardSuccess && url == NULL);
	CFURLRef place = CFURLCreateWithString(NULL, CFSTR("file:///tmp/dropped/"), NULL);
	CHECK(CFPasteboardSetPasteLocation(pb, place) == kCFPasteboardSuccess);
	CHECK(CFPasteboardCopyPasteLocation(pb, &url) == kCFPasteboardSuccess && url != NULL && CFEqual(url, place));
	CFRelease(url);
	CFPasteboardBeginGeneration(pb);   // a new generation forgets it
	CHECK(CFPasteboardCopyPasteLocation(pb, &url) == kCFPasteboardSuccess && url == NULL);
	CFRelease(place);
	CFPasteboardReleaseGlobally(pb);
	CFRelease(pb);
}

// ---- host bridge ----
static int changed, lazyAsked;
static void bridgeChanged(CFStringRef name, CFPasteboardRef pb, void *info) { changed++; }
static CFDataRef bridgeCopyData(CFStringRef name, CFIndex itemIndex, CFStringRef flavor, void *info) {
	lazyAsked++;
	return itemIndex == 1 && CFEqual(flavor, kPNG) ? bytes("png-from-host") : NULL;
}

// ---- another client of the service ----

static xpc_object_t call(xpc_connection_t peer, xpc_object_t request) {
	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(peer, request);
	xpc_release(request);
	return reply;
}
static int64_t statusOf(xpc_object_t reply) {
	return xpc_get_type(reply) == XPC_TYPE_DICTIONARY ? xpc_dictionary_get_int64(reply, CFPB_KEY_STATUS) : -1000;
}
static xpc_object_t request(int op, CFStringRef name) {
	xpc_object_t r = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(r, CFPB_KEY_OP, op);
	if (name != NULL) {
		char buffer[300];
		CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8);
		xpc_dictionary_set_string(r, CFPB_KEY_NAME, buffer);
	}
	return r;
}
static int64_t simple(xpc_connection_t peer, xpc_object_t r) {
	xpc_object_t reply = call(peer, r);
	int64_t status = statusOf(reply);
	xpc_release(reply);
	return status;
}
static void waitFor(int *counter, int wanted) {
	for (int i = 0; i < 200 && *counter < wanted; i++) usleep(10000);
}

static void testPeers(xpc_endpoint_t endpoint) {
	xpc_connection_t peer = xpc_connection_create_from_endpoint(endpoint);
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {});
	xpc_connection_resume(peer);

	CFPasteboardRef pb = CFPasteboardCreateUnique(NULL);
	CFStringRef name = CFPasteboardCopyName(pb);
	provided = allProvided = ownerChanged = released = 0;
	CFIndex c1 = CFPasteboardBeginGeneration(pb);
	CFPasteboardItemID item = 0;
	CFPasteboardAddItem(pb, &item);
	CFDataRef hello = bytes("hello");
	CFPasteboardSetData(pb, item, kText, hello, 0);
	CFRelease(hello);
	CHECK(CFPasteboardPromiseData(pb, item, kPNG, 0, &provider, "peer-asked") == kCFPasteboardSuccess);

	// the peer sees the board, reads it, may not write to it
	xpc_object_t r = request(CFPB_OP_INFO, name);
	xpc_object_t reply = call(peer, r);
	CHECK(statusOf(reply) == 0 && (CFIndex)xpc_dictionary_get_uint64(reply, CFPB_KEY_COUNT) == c1 && xpc_dictionary_get_int64(reply, CFPB_KEY_ITEMS) == 1);
	CHECK(!xpc_dictionary_get_bool(reply, CFPB_KEY_OWNED));
	xpc_release(reply);
	r = request(CFPB_OP_DATA, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, item);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	reply = call(peer, r);
	size_t length = 0;
	const char *got = statusOf(reply) == 0 && xpc_dictionary_get_value(reply, CFPB_KEY_DATA) ? xpc_dictionary_get_data(reply, CFPB_KEY_DATA, &length) : NULL;
	CHECK(got != NULL && length == 5 && memcmp(got, "hello", 5) == 0);
	xpc_release(reply);
	r = request(CFPB_OP_SET, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, item);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.html");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, 0);
	CHECK(simple(peer, r) == kCFPasteboardNotOwner);
	r = request(CFPB_OP_RELEASE, name);
	CHECK(simple(peer, r) != kCFPasteboardSuccess);   // only the creator may drop a unique board

	// reading a promise through the peer makes the service ask this process's provider
	r = request(CFPB_OP_DATA, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, item);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.png");
	xpc_dictionary_set_bool(r, CFPB_KEY_RESOLVE, true);
	reply = call(peer, r);
	got = statusOf(reply) == 0 && xpc_dictionary_get_value(reply, CFPB_KEY_DATA) ? xpc_dictionary_get_data(reply, CFPB_KEY_DATA, &length) : NULL;
	CHECK(got != NULL && length == 10 && memcmp(got, "peer-asked", 10) == 0);
	xpc_release(reply);
	CHECK(provided == 1 && allProvided == 1);

	// the peer takes the board over: this process is told, and may no longer write
	r = request(CFPB_OP_BEGIN, name);
	reply = call(peer, r);
	CHECK(statusOf(reply) == 0 && (CFIndex)xpc_dictionary_get_uint64(reply, CFPB_KEY_COUNT) == c1 + 1);
	xpc_release(reply);
	waitFor(&ownerChanged, 1);
	CHECK(ownerChanged == 1 && released == 1);
	CHECK(CFPasteboardGetChangeCount(pb) == c1 + 1);
	CFDataRef data = bytes("mine");
	CHECK(CFPasteboardSetData(pb, 1, kText, data, 0) == kCFPasteboardNotOwner);
	CFRelease(data);
	r = request(CFPB_OP_SET, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, 9);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, 0);
	xpc_dictionary_set_data(r, CFPB_KEY_DATA, "theirs", 6);
	CHECK(simple(peer, r) == 0);
	CHECK(CFPasteboardCopyData(pb, 9, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "theirs"));
	CFRelease(data);

	// a promise by a client that goes away is dropped with it
	r = request(CFPB_OP_BEGIN, name);
	CHECK(simple(peer, r) == 0);
	r = request(CFPB_OP_SET, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, 3);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, 0);
	xpc_dictionary_set_bool(r, CFPB_KEY_PROMISED, true);
	CHECK(simple(peer, r) == 0);
	CHECK(CFPasteboardIsDataPromised(pb, 3, kText));
	xpc_connection_cancel(peer);
	CFDataRef none = NULL;
	for (int i = 0; i < 200 && CFPasteboardCopyData(pb, 3, kText, &none) != kCFPasteboardBadFlavor; i++) usleep(10000);
	CHECK(CFPasteboardCopyData(pb, 3, kText, &none) == kCFPasteboardBadFlavor);
	xpc_release(peer);

	CFPasteboardReleaseGlobally(pb);
	CFRelease(pb);
	CFRelease(name);
}

// Malformed requests are refused and do not harm the service
static void testMalformed(xpc_endpoint_t endpoint) {
	xpc_connection_t peer = xpc_connection_create_from_endpoint(endpoint);
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {});
	xpc_connection_resume(peer);
	CFStringRef good = CFSTR("test.malformed");
	CHECK(simple(peer, xpc_dictionary_create(NULL, NULL, 0)) == kCFPasteboardInvalid);   // no op
	xpc_object_t r = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(r, CFPB_KEY_OP, "open");   // op of the wrong type
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_LAST, good);
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(-5, good);
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_INFO, NULL);   // no name
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(r, CFPB_KEY_OP, CFPB_OP_INFO);
	xpc_dictionary_set_int64(r, CFPB_KEY_NAME, 7);   // name of the wrong type
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	char longName[400];
	memset(longName, 'n', sizeof(longName) - 1);
	longName[sizeof(longName) - 1] = 0;
	r = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(r, CFPB_KEY_OP, CFPB_OP_OPEN);
	xpc_dictionary_set_string(r, CFPB_KEY_NAME, longName);
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_ITEM_AT, good);   // missing index
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_ITEM_AT, good);
	xpc_dictionary_set_string(r, CFPB_KEY_INDEX, "0");   // index of the wrong type
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_SET, good);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, 1);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, (uint64_t)1 << 40);   // flags that do not fit
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_SET, good);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, 1);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, 0);
	xpc_dictionary_set_string(r, CFPB_KEY_DATA, "not data");   // data of the wrong type
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	r = request(CFPB_OP_SET_LOCATION, good);
	xpc_dictionary_set_string(r, CFPB_KEY_LOCATION, "");
	CHECK(simple(peer, r) == kCFPasteboardInvalid);
	// and the service still answers
	CHECK(simple(peer, request(CFPB_OP_HELLO, NULL)) == 0);
	xpc_connection_cancel(peer);
	xpc_release(peer);
}

// ---- the bridge with the service as the single store ----

static int pushes, hostPushes;
static void waitForAbove(int *counter, int value) {
	for (int i = 0; i < 300 && *counter <= value; i++) usleep(10000);
}

// A windowless client (a raw peer) and the bridged client share the general board through the service. The fake
// bridge here is notified of the peer's changes, a host import reaches the peer marked as such, and the peer reads a
// lazily imported flavor through the bridge's provider.
static void testBridgeThroughService(xpc_endpoint_t endpoint, CFPasteboardRef general, CFArrayRef items) {
	CFStringRef name = CFSTR("Apple CFPasteboard general");
	xpc_connection_t peer = xpc_connection_create_from_endpoint(endpoint);
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
		if (xpc_get_type(event) == XPC_TYPE_DICTIONARY && xpc_dictionary_get_int64(event, CFPB_KEY_OP) == CFPB_OP_PUSH_CHANGED) {
			pushes++;
			if (xpc_dictionary_get_bool(event, CFPB_KEY_HOST)) hostPushes++;
		}
	});
	xpc_connection_resume(peer);
	CHECK(simple(peer, request(CFPB_OP_SUBSCRIBE, name)) == 0);

	// a host import is announced to other subscribers as an import
	int before = pushes, hostBefore = hostPushes;
	CFIndex count = CFPasteboardHostBridgeReplaceContents(kCFPasteboardGeneral, items);
	CHECK(count != 0);
	waitForAbove(&pushes, before);
	CHECK(pushes > before && hostPushes > hostBefore && hostPushes - hostBefore == pushes - before);

	// the peer (windowless: no bridge) writes the general board; the bridge hears of it, and the peer is not told of its own change
	before = pushes;
	int notified = changed;
	xpc_object_t reply = call(peer, request(CFPB_OP_BEGIN, name));
	CHECK(statusOf(reply) == 0);
	xpc_release(reply);
	reply = call(peer, request(CFPB_OP_ADD_ITEM, name));
	CHECK(statusOf(reply) == 0);
	uint64_t id = xpc_dictionary_get_uint64(reply, CFPB_KEY_ITEM);
	xpc_release(reply);
	xpc_object_t r = request(CFPB_OP_SET, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, id);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.utf8-plain-text");
	xpc_dictionary_set_uint64(r, CFPB_KEY_FLAGS, 0);
	xpc_dictionary_set_data(r, CFPB_KEY_DATA, "windowless", 10);
	CHECK(simple(peer, r) == 0);
	waitForAbove(&changed, notified + 2);
	CHECK(changed >= notified + 3);   // new generation, item, flavor
	CHECK(pushes == before);
	CFDataRef data = NULL;
	CFIndex n = 0;
	CFPasteboardItemID item = 0;
	CHECK(CFPasteboardGetItemCount(general, &n) == kCFPasteboardSuccess && n == 1);
	CHECK(CFPasteboardGetItemAtIndex(general, 0, &item) == kCFPasteboardSuccess && item == id);
	CHECK(CFPasteboardCopyData(general, item, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "windowless"));
	CFRelease(data);

	// the bridge imports from the host again; the peer reads the lazy flavor and the bridge's provider supplies it
	CHECK(CFPasteboardHostBridgeReplaceContents(kCFPasteboardGeneral, items) != 0);
	int asked = lazyAsked;
	r = request(CFPB_OP_DATA, name);
	xpc_dictionary_set_uint64(r, CFPB_KEY_ITEM, 2);
	xpc_dictionary_set_string(r, CFPB_KEY_FLAVOR, "public.png");
	xpc_dictionary_set_bool(r, CFPB_KEY_RESOLVE, true);
	reply = call(peer, r);
	size_t length = 0;
	const char *got = statusOf(reply) == 0 && xpc_dictionary_get_value(reply, CFPB_KEY_DATA) ? xpc_dictionary_get_data(reply, CFPB_KEY_DATA, &length) : NULL;
	CHECK(got != NULL && length == 13 && memcmp(got, "png-from-host", 13) == 0 && lazyAsked == asked + 1);
	xpc_release(reply);
	// the bridge's own import is not reported to the bridge
	int settled = changed;
	usleep(100000);
	CHECK(changed == settled);

	xpc_connection_cancel(peer);
	xpc_release(peer);
}

static void testBridge(xpc_endpoint_t endpoint) {
	CFPasteboardHostBridgeCallbacks bridge = { 0, bridgeChanged, bridgeCopyData, NULL };
	CHECK(CFPasteboardRegisterHostBridge(&bridge));
	CHECK(!CFPasteboardRegisterHostBridge(&bridge));

	CFPasteboardRef general = CFPasteboardCreate(NULL, kCFPasteboardGeneral);
	CFPasteboardRef find = CFPasteboardCreate(NULL, kCFPasteboardFind);
	CHECK(general != NULL && find != NULL);
	CFStringRef name = CFPasteboardCopyName(general);
	CHECK(CFEqual(name, CFSTR("Apple CFPasteboard general")));
	CFRelease(name);

	changed = 0;
	CFPasteboardBeginGeneration(general);
	CHECK(changed == 1);
	CFPasteboardItemID item;
	CFPasteboardAddItem(general, &item);
	CFDataRef text = bytes("local");
	CFPasteboardSetData(general, item, kText, text, 0);
	CHECK(changed == 3);
	CFRelease(text);
	CFPasteboardBeginGeneration(find);   // not bridged
	CHECK(changed == 3);

	// the host's clipboard changed: two items, the second one's png is fetched on demand
	CFMutableDictionaryRef first = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFMutableDictionaryRef secondItem = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDataRef host = bytes("from host");
	CFDictionarySetValue(first, kText, host);
	CFDictionarySetValue(secondItem, kText, host);
	CFDictionarySetValue(secondItem, kPNG, kCFNull);
	CFRelease(host);
	const void *itemValues[] = { first, secondItem };
	CFArrayRef items = CFArrayCreate(NULL, itemValues, 2, &kCFTypeArrayCallBacks);
	CFIndex before = CFPasteboardGetChangeCount(general);
	CHECK(CFPasteboardHostBridgeReplaceContents(kCFPasteboardGeneral, items) == before + 1);
	CHECK(changed == 3);   // not reported back to the bridge
	CFIndex count = 0;
	CHECK(CFPasteboardGetItemCount(general, &count) == kCFPasteboardSuccess && count == 2);
	CFPasteboardItemID one = 0, two = 0;
	CHECK(CFPasteboardGetItemAtIndex(general, 0, &one) == kCFPasteboardSuccess && CFPasteboardGetItemAtIndex(general, 1, &two) == kCFPasteboardSuccess);
	CFDataRef data = NULL;
	CHECK(CFPasteboardCopyData(general, one, kText, &data) == kCFPasteboardSuccess && dataEquals(data, "from host"));
	CFRelease(data);
	CHECK(CFPasteboardIsDataPromised(general, two, kPNG) && lazyAsked == 0);
	CHECK(CFPasteboardCopyData(general, two, kPNG, &data) == kCFPasteboardSuccess && dataEquals(data, "png-from-host") && lazyAsked == 1);
	CFRelease(data);
	// the process may not write into what the host put there without starting a generation
	CHECK(CFPasteboardHostBridgeReplaceContents(kCFPasteboardFind, items) == 0);
	if (endpoint != NULL) testBridgeThroughService(endpoint, general, items);
	CFRelease(items); CFRelease(first); CFRelease(secondItem);
	CFRelease(general); CFRelease(find);
}

int main(int argc, char **argv) {
	// "service": the boards live in a service running inside this process, a second client talks to it as well
	xpc_endpoint_t endpoint = NULL;
	if (argc > 1 && strcmp(argv[1], "service") == 0) {
		endpoint = __CFPasteboardStartInProcessService();
		__CFPasteboardAdoptServiceEndpoint(endpoint);
	}
	testBasics();
	testInvalid();
	testPromises();
	testPasteLocation();
	if (endpoint != NULL) {
		testPeers(endpoint);
		testMalformed(endpoint);
	}
	testBridge(endpoint);
	if (failures == 0) printf("PASS\n");
	return failures ? 1 : 0;
}
