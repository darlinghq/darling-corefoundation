# NSException backtrace edge cases

Build `NSExceptionBacktraceEdgeCases.m` and `NSExceptionBacktraceHook.c`
against Foundation and run inside Darling:

```sh
guest-cc.sh -o NSExceptionBacktraceHook.dylib NSExceptionBacktraceHook.c -dynamiclib -install_name @rpath/NSExceptionBacktraceHook.dylib
guest-cc.sh -o NSExceptionBacktraceEdgeCases NSExceptionBacktraceEdgeCases.m -framework Foundation
for m in 0 1 n 2 real; do
  TEST_BACKTRACE_MODE=$m DYLD_INSERT_LIBRARIES=$PWD/NSExceptionBacktraceHook.dylib ./NSExceptionBacktraceEdgeCases
done
```

Checks:
- `TEST_BACKTRACE_MODE=0`: `backtrace()` returns `0` (must not underflow `count - 1`
  to `(NSUInteger)-1` in `+[__NSArrayI __new:::]` or segfault in `CFRetain`; returns
  empty `callStackSymbols` and `callStackReturnAddresses`).
- `TEST_BACKTRACE_MODE=1`: `backtrace()` returns `1` (only the instantiator frame;
  returns empty arrays).
- `TEST_BACKTRACE_MODE=n`: `backtrace_symbols()` returns `NULL` (does not crash).
- `TEST_BACKTRACE_MODE=2`: `backtrace_symbols()` returns an invalid UTF-8 string
  where `CFStringCreateWithCString(..., kCFStringEncodingUTF8)` returns `NULL`
  (falls back to `"%p"` formatted address instead of passing `NULL` to `CFRetain`).
- `TEST_BACKTRACE_MODE=real`: normal `[NSException raise:...]` still captures stack frames.

Baseline (`CoreFoundation` without this fix): `TEST_BACKTRACE_MODE=0` crashes
with SIGSEGV (exit 139).
Candidate: all 5 modes print `PASS` and exit 0.
