# Main dispatch queue servicing by CFRunLoop

Build `cfrunloop_main_queue.c` against CoreFoundation and run it under Darling with a timeout. It checks four things: a zero-timeout run loop that always has a due timer still services the main queue; a mode that is not a common mode does not; a block submitted from another thread wakes a run loop sleeping in a common mode; and a nested run inside a main-queue block does not service the main queue.

Before the fix the starvation check (the queued block never runs while the always-due timer keeps the loop busy) and the common-mode check fail; after it all pass.
