# NSInvocation and forwarding across calling conventions

`nsinvocation-abi.m` invokes methods through NSInvocation and through `forwardInvocation:` with narrow integers, floats, doubles, structs of 8, 16 and 40 bytes, a four-double aggregate and arguments that spill to the stack, and checks the results. The last check sends `forwardInvocation:` to `super` from a class whose `methodSignatureForSelector:` accepts the selector; the default implementation must raise `NSInvalidArgumentException` (it used to re-invoke the invocation on the target, which recursed until the stack overflowed). It prints `N/N passed`.

The register and stack rules it covers are the arm64 ones; on x86_64 the same cases pass before and after, apart from the `super` check. On arm64 the invoke trampolines used to read the return type as a pointer, so most cases crashed.
