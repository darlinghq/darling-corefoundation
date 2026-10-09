# CFError underlying error

Build CFErrorUnderlyingError.m against Foundation/CoreFoundation and run it under Darling as a non-root user. It creates and removes its own mkdtemp directory. This replicates the Stickies crash, where NSLog of an NSError whose `NSUnderlyingErrorKey` held a CFString faulted in `CFDictionaryGetValue`.

Checks: a failed `NSURLIsRegularFileKey` lookup on a missing file and a `CFURLEnumerator` walk into an unreadable directory each return a POSIX error whose underlying error is a POSIX `CFError` with the same errno (`ENOENT`, `EACCES`), and both errors can be logged and described. The enumerator uses `kCFURLEnumeratorDefaultBehavior` because the current enumerator descends into subdirectories only without `kCFURLEnumeratorDescendRecursively`. Three more checks describe errors whose underlying value is a `CFString`, an `NSString` and an `NSError`.

Installed baseline: `FAIL NSURL missing file: underlying error is a CFError`, then a segmentation fault (exit 139) at the first NSLog. Candidate: `failures=0`.
