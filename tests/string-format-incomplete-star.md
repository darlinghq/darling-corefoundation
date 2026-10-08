# Incomplete `*` format specifiers

`string-format-incomplete-star.c` formats `abc%*`, `abc%.*` and a complete `%*d` through `CFStringCreateWithFormat` and checks the results (`abc`, `abc`, `   7`). It prints `3/3 passed` on success.

The bug is a silent out-of-bounds read, so the output alone is identical before and after the fix: `__CFStringAppendFormatCore` kept the `-2` marker that `*` sets on an incomplete (type 0) spec and then read `values[-2]`. To see it, build two CoreFoundation dylibs that differ only in `CFString.o` and print the index at each width/precision read (a throwaway `fprintf` in the two `if` bodies, not part of this change). Before the fix the run prints `width index=-2` and `precision index=-2`; after the fix neither line appears and the `%*d` read (`index=0`) still does.
