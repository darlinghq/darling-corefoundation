# CFXPCBridge primitives

Build `cfxpcbridge-primitives.c` against CoreFoundation and libxpc and run it under Darling.

`CFXPCBridge.h` declares conversion functions between XPC objects and CoreFoundation objects. The XPC object API defines `XPC_TYPE_DOUBLE`, `XPC_TYPE_DATE` and `XPC_TYPE_UUID` and their value accessors. The test converts each primitive from XPC to CoreFoundation and back, checking the resulting type and exact value. XPC date values are integer nanoseconds from the Unix epoch; CFDate values are seconds from the Core Foundation epoch, so a one-day XPC date must become 86400 seconds from the CF epoch and back to the same nanosecond count.

Installed baseline: `_CFXPCCreateCFObjectFromXPCObject` returns NULL for all three types and `_CFXPCCreateXPCObjectFromCFObject` returns NULL for CFNumber values created from floating-point numbers, CFDate and CFUUID; candidate: zero failures.

## Provenance

Behavior is taken from the public XPC object API declarations in `xpc.h` and the public CoreFoundation type APIs (`CFNumber`, `CFDate`, `CFUUID`). The epoch relationship is the documented definition of `CFAbsoluteTime` and the XPC date accessor's nanosecond value. No restricted material was used.
