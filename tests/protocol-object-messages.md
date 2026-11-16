# Protocol objects as ordinary objects

Build protocol-object-messages.m against Foundation (without -fobjc-arc, for i386 and x86_64) and run it under Darling (or on macOS, where it passes). It retains and releases a Protocol, stores it in a strong variable through objc_storeStrong, puts it in collections and sends it the basic NSObject messages.

Installed baseline: on i386 the first retain crashes in message forwarding (stack exhaustion); x86_64 passes. Candidate: PASS on both.
