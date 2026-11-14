# Exception unwinding through an autorelease pool drain

Build `exception-survives-pool-drain.m` against Foundation for i386 and for x86_64 and run both under Darling. It raises (through a block, as a plain function call and nested) under an `@finally` that drains an autorelease pool, and catches the autoreleased exception outside; it also raises inside a `@catch` body, rethrows, and catches a thousand exceptions in a loop.

On i386 before the fix the exception is freed by the pool drain: the `@catch` does not match and the process aborts with "uncaught exception of class nil". After the fix, and always on x86_64, it prints `PASS`.
