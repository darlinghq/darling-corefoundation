# NSURLTypeIdentifierKey

Build URLTypeIdentifier.m against Foundation/CoreFoundation and run it under Darling. It reads `NSURLTypeIdentifierKey` for a directory without an extension (`public.folder`), a `.txt` file (`public.plain-text`) and a missing path (an error, no value), and checks the value equals the `NSURLContentTypeKey` type's identifier.

Expected on the installed baseline: failures (the directory case traps in `CFRelease(NULL)`, the file case returns NO); candidate: zero failures.
