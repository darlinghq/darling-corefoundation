#include <stdio.h>

// Diagnostics that must survive a release build, so this cannot be compiled out.
// stderr rather than stdout: it is unbuffered, so the message still reaches the terminal
// when the process is about to die by signal, and it is where macOS writes these.
#define RELEASE_LOG(fmt, ...) fprintf(stderr, fmt "\n", ##__VA_ARGS__)
#define DEBUG_LOG(fmt, ...)
#define DEBUG_BREAK() __builtin_trap()
#define UNLIKELY(x) __builtin_expect((x),0)
