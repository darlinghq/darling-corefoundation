# NSURL resource value ownership

Build nsurl-resource-value-ownership.m against Foundation and run it under Darling. A temporary resource value is held only by the URL's resource cache. `-getResourceValue:forKey:error:` must hand it out autoreleased, so it is still alive after the URL is released and is freed when the pool is drained; `CFURLCopyResourcePropertyForKey` must follow the Copy rule (the caller owns one reference and releases it, which must not free the cached value). A tracked value read with a NULL out pointer must not be left with an extra reference, so it is freed with the URL.

Expected before the change: the tracked value is freed together with the URL and a second read after the caller's release returns a dangling value; after: zero failures.
