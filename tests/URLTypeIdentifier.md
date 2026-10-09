# NSURLTypeIdentifierKey

Build URLTypeIdentifier.m against Foundation/CoreFoundation and run it under Darling. It reads `NSURLTypeIdentifierKey` for a directory without an extension (`public.folder`), a `.txt` file (`public.plain-text`), an extensionless file, and a missing path (an error, no value), and checks the value equals the `NSURLContentTypeKey` type's identifier.

Expected on the installed baseline: failures (the directory case traps with SIGTRAP before any PASS line); candidate: zero failures.

Limitations: extensions declared only by an installed app (via the LaunchServices database) yield a `dyn.*` identifier, the same gap as #972. Unknown extensions yield Darling's `dyn.*` identifier rather than an error.
