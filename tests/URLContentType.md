# URL content type

Build URLContentType.m against Foundation/CoreFoundation and run it under Darling with UniformTypeIdentifiers installed. It creates and removes its own mkdtemp directory. Eleven checks read `NSURLContentTypeKey` for files with known, unknown and no extensions, an executable, a plain directory, an `.app` directory, a directory with a file extension, a symbolic link, a missing file (error), and through `resourceValuesForKeys:` together with another key.

Installed baseline: eleven failures (no value); candidate: zero failures. Volume roots are reported as `public.folder` (macOS: `public.volume`), since Darling does not detect volumes for `NSURLIsVolumeKey` either.
