# CFURLCopyResourcePropertyForKey ownership

Build cfurl-copy-resource-ownership.c against CoreFoundation and run it under Darling. It creates and removes its own mkdtemp directory under /tmp.

Checks:
1. A copy of kCFURLContentModificationDateKey holds two references: the URL's cache and the caller's. The program stops here on failure, before any release, so it never reads freed memory.
2. After one release, a second copy returns the same date and two references.
3. After the URL is released and 4000 CFDates are allocated, the copied date still has its value (the authd sequence).
4. A copy with a NULL out pointer leaves the cached count unchanged.
5. CFURLCreateBookmarkData releases its copy of the requested property so the cached date holds one reference (two when read back, one after releasing the read-back).

Before the change the first copy holds one reference (the caller owns nothing), so check 1 fails and the program exits 1. After the change all checks pass.
