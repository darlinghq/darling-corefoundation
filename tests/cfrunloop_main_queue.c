/*
 * Copyright (C) 2026 Lubos Dolezel
 */

/*
 * Main dispatch queue servicing by CFRunLoop on the main thread.
 *
 * Contract (documented: the main queue is serviced by the main run loop in
 * the common modes, from the base run loop invocation; blocks submitted from
 * any thread run in order):
 *  1. A zero-timeout run loop that is always busy (a timer that is always
 *     due) still services the main queue: a submitted block runs within a
 *     bounded number of runs, even when every run is a single pass.
 *  2. A mode that is not a common mode does not service the main queue; the
 *     block stays queued and runs once a common mode runs.
 *  3. Once the mode is a common mode, a block submitted from another thread
 *     while the run loop sleeps in that mode wakes it and runs promptly.
 *  4. A nested run inside a main-queue block does not service the main queue
 *     (the block queued meanwhile runs after the outer block returns).
 *
 * Expected output: PASS, exit 0. Run under a host-side timeout.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
static volatile int ran;
static int order[3], order_n;

#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL %s\n", what); failures++; } } while (0)

static void busy_timer(CFRunLoopTimerRef t, void *info) { (void)t; (void)info; }

static double now(void)
{
	return CFAbsoluteTimeGetCurrent();
}

static void *submit_after(void *arg)
{
	usleep((useconds_t)(intptr_t)arg);
	dispatch_async(dispatch_get_main_queue(), ^{ ran++; });
	return NULL;
}

static void submit_later(useconds_t us)
{
	pthread_t t;
	pthread_create(&t, NULL, submit_after, (void *)(intptr_t)us);
	pthread_detach(t);
}

int main(void)
{
	CFRunLoopRef rl = CFRunLoopGetCurrent();

	// 1. always-due timer, single-pass zero-timeout runs
	CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), 1e-6, 0, 0, busy_timer, NULL);
	CFRunLoopAddTimer(rl, timer, kCFRunLoopDefaultMode);
	ran = 0;
	dispatch_async(dispatch_get_main_queue(), ^{ ran++; });
	int runs = 0;
	while (!ran && runs < 1000) {
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
		runs++;
	}
	CHECK(ran == 1, "1: main queue starved by an always-due timer");
	CFRunLoopRemoveTimer(rl, timer, kCFRunLoopDefaultMode);
	CFRelease(timer);

	// 2. a mode that is not common does not service the main queue
	CFStringRef custom = CFSTR("org.darlinghq.test.custom");
	ran = 0;
	submit_later(50000);
	CFRunLoopSourceContext sctx = {0};
	CFRunLoopSourceRef keep = CFRunLoopSourceCreate(NULL, 0, &sctx);
	CFRunLoopAddSource(rl, keep, custom); // a run needs a source to wait
	CFRunLoopRunInMode(custom, 0.3, false);
	CHECK(ran == 0, "2: non-common mode serviced the main queue");
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
	CHECK(ran == 1, "2: queued block did not run in a common mode");

	// 3. mode becomes common; a block submitted while sleeping wakes the run
	CFRunLoopAddCommonMode(rl, custom);
	ran = 0;
	submit_later(150000);
	double t0 = now();
	CFRunLoopRunInMode(custom, 5, true);
	double dt = now() - t0;
	CHECK(ran == 1, "3: block submitted while sleeping did not run");
	CHECK(dt < 2.0, "3: sleeping run was not woken promptly");

	// the same again after another run of the mode (the port is reused)
	ran = 0;
	submit_later(150000);
	t0 = now();
	CFRunLoopRunInMode(custom, 5, true);
	dt = now() - t0;
	CHECK(ran == 1 && dt < 2.0, "3: second wake-up lost");

	// 4. nested run inside a main-queue block does not service the queue
	order_n = 0;
	dispatch_async(dispatch_get_main_queue(), ^{
		order[order_n++] = 1;
		dispatch_async(dispatch_get_main_queue(), ^{ order[order_n++] = 3; });
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
		order[order_n++] = 2;
	});
	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
	CHECK(order_n == 3 && order[0] == 1 && order[1] == 2 && order[2] == 3, "4: nested run serviced the main queue");

	CFRelease(keep);
	if (!failures)
		puts("PASS");
	return failures != 0;
}
