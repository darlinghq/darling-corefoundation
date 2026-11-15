# NSURLContentTypeKey

Build URLContentType.m against Foundation and UniformTypeIdentifiers and run it under Darling. It reads `NSURLContentTypeKey` for a `.txt` file (UTType `public.plain-text`), a directory (`public.folder`), a file with an unknown extension (a dynamic type conforming to `public.data`) and a missing path (NSCocoaErrorDomain 260 with POSIX ENOENT underneath), and checks that the UTType's identifier equals `NSURLTypeIdentifierKey`.

Expected before the change: the value is nil for every path and the missing path reports no error; after: zero failures.
