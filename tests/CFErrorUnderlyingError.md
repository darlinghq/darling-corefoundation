# CFError underlying error

Build CFErrorUnderlyingError.m against Foundation/CoreFoundation and run it under Darling as a non-root user. It creates and removes its own mkdtemp directory. This replicates the Stickies crash, where NSLog of an NSError whose `NSUnderlyingErrorKey` held a CFString faulted in `CFDictionaryGetValue`.

Checks: a failed `NSURLIsRegularFileKey` lookup on a missing file and a `CFURLEnumerator` walk into an unreadable directory each return a Cocoa file reading error (`NSFileReadNoSuchFileError` 260, `NSFileReadNoPermissionError` 257) whose underlying error is a POSIX `CFError` with the errno (`ENOENT`, `EACCES`), and both errors can be logged and described. The enumerator uses `kCFURLEnumeratorDescendRecursively`: with the default behavior it lists the unreadable directory's name and never opens it, on macOS 10.14.4 and 26.7.3 as well as in Darling. Three more checks describe errors whose underlying value is a `CFString`, an `NSString` and an `NSError` (macOS 10.14.4 itself faults on the `CFString` one, which is the crash this test replicates).

Installed baseline: `FAIL NSURL missing file: underlying error is a CFError`, then a segmentation fault (exit 139) at the first NSLog. Candidate: `failures=0`.
