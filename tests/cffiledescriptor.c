/*
 * Copyright (C) 2026 Lubos Dolezel
 */

/*
 * CFFileDescriptor: a run loop source reporting readability and writability.
 *
 * Contract (documented: callbacks are enabled per condition and each enabled
 * callback is delivered once, then disabled until enabled again; invalidating
 * invalidates the run loop source and closes the descriptor when asked to;
 * the context's retain and release callbacks bracket the context's lifetime):
 *  1. Type id, native descriptor and context accessors.
 *  2. A read callback is not delivered without data, is delivered once when
 *     data arrives, is not repeated while data stays unread, and is delivered
 *     again after it is enabled again.
 *  3. Callbacks that are not enabled are not delivered.
 *  4. A write callback is delivered for a descriptor that can be written.
 *  5. Invalidate closes the descriptor only when closeOnInvalidate is true,
 *     invalidates the run loop source, and a source cannot be created from
 *     an invalid descriptor.
 *  6. The context is retained when the descriptor is created and released
 *     when it is invalidated.
 *
 * Expected output: PASS, exit 0. Run under a host-side timeout.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFFileDescriptor.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures;
static int calls;
static CFOptionFlags last_types;
static int retains, releases;
static int stop_on_call = 1;

#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL %s\n", what); failures++; } } while (0)

static void callback(CFFileDescriptorRef f, CFOptionFlags types, void *info)
{
	(void)f;
	CHECK(*(int *)info == 42, "callback receives the context info");
	calls++;
	last_types = types;
	if (stop_on_call)
		CFRunLoopStop(CFRunLoopGetCurrent());
}
static void *retain_info(void *info) { retains++; return info; }
static void release_info(void *info) { (void)info; releases++; }

static void spin(double seconds)
{
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

int main(void)
{
	int fds[2];
	int info = 42;
	CFFileDescriptorContext context = {0, &info, retain_info, release_info, NULL};

	if (pipe(fds) != 0)
		return 2;
	CFFileDescriptorRef f = CFFileDescriptorCreate(NULL, fds[0], true, callback, &context);
	CHECK(f != NULL, "create");
	CHECK(CFGetTypeID(f) == CFFileDescriptorGetTypeID(), "type id");
	CHECK(CFFileDescriptorGetNativeDescriptor(f) == fds[0], "native descriptor");
	CHECK(CFFileDescriptorIsValid(f), "valid");
	CHECK(retains == 1 && releases == 0, "context retained at creation");
	CFFileDescriptorContext got;
	memset(&got, 0, sizeof(got));
	CFFileDescriptorGetContext(f, &got);
	CHECK(got.info == &info, "context accessor");

	CFRunLoopSourceRef source = CFFileDescriptorCreateRunLoopSource(NULL, f, 0);
	CHECK(source != NULL && CFRunLoopSourceIsValid(source), "run loop source");
	CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);

	CFFileDescriptorEnableCallBacks(f, kCFFileDescriptorReadCallBack);
	spin(0.3);
	CHECK(calls == 0, "no read callback without data");

	CHECK(write(fds[1], "x", 1) == 1, "write data");
	spin(2);
	CHECK(calls == 1 && last_types == kCFFileDescriptorReadCallBack, "read callback when data arrives");
	CHECK(retains == 2 && releases == 1, "context retained around the callback");
	spin(0.3);
	CHECK(calls == 1, "read callback delivered once while data stays unread");

	CFFileDescriptorEnableCallBacks(f, kCFFileDescriptorReadCallBack);
	spin(2);
	CHECK(calls == 2, "read callback delivered again after enabling");

	// Callbacks that are not enabled are not delivered, even though data is still waiting.
	spin(0.3);
	CHECK(calls == 2, "disabled callback not delivered");

	CFFileDescriptorInvalidate(f);
	CHECK(!CFFileDescriptorIsValid(f), "invalid after invalidate");
	CHECK(!CFRunLoopSourceIsValid(source), "run loop source invalid after invalidate");
	CHECK(close(fds[0]) == -1 && errno == EBADF, "descriptor closed by invalidate");
	CHECK(releases == retains, "context released at invalidate");
	CHECK(CFFileDescriptorCreateRunLoopSource(NULL, f, 0) == NULL, "no source from an invalid descriptor");
	CFRelease(source);
	CFRelease(f);

	// Writability, and a descriptor that is not closed on invalidate.
	int pipe2[2];
	if (pipe(pipe2) != 0)
		return 2;
	calls = 0;
	CFFileDescriptorRef w = CFFileDescriptorCreate(NULL, pipe2[1], false, callback, &context);
	CFRunLoopSourceRef wsource = CFFileDescriptorCreateRunLoopSource(NULL, w, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), wsource, kCFRunLoopDefaultMode);
	CFFileDescriptorEnableCallBacks(w, kCFFileDescriptorWriteCallBack);
	spin(2);
	CHECK(calls == 1 && last_types == kCFFileDescriptorWriteCallBack, "write callback");
	CFFileDescriptorInvalidate(w);
	CHECK(write(pipe2[1], "a", 1) == 1, "descriptor left open when not asked to close it");
	CFRelease(wsource);
	CFRelease(w);
	close(pipe2[0]);
	close(pipe2[1]);
	close(fds[1]);

	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
