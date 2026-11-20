# CFURLEnumerator paths and invisible files

Build CFURLEnumeratorPaths.m against Foundation/CoreFoundation and run it under Darling. It creates and removes its own mkdtemp directory with a directory named "a b" in it.

Checks:
1. A directory URL whose path is percent-escaped (`a%20b`) is enumerated, through CFURLEnumerator and NSFileManager.
2. A directory URL relative to a base URL, as `-[NSBundle resourceURL]` returns, is enumerated, also after `URLByAppendingPathComponent:`.
3. `kCFURLEnumeratorSkipInvisibles` / `NSDirectoryEnumerationSkipsHiddenFiles` leave out dot files and the contents of dot directories.
4. `NSDirectoryEnumerationSkipsSubdirectoryDescendants` stays flat.

The expected listings are those of macOS 26.7.3 and Mac OS X 10.14.4. Before the change every listing is empty or keeps the hidden files; after it all nine checks pass.
