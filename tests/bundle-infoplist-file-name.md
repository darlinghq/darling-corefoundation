# Info.plist found under a differently cased name

Build `bundle-infoplist-file-name.c` against CoreFoundation and run it under Darling (a case-sensitive file system). It creates bundles whose Info.plist is spelled `info.plist` (in `Contents`) or `INFO.PLIST` (flat bundle), and a normal one, and reads each with `CFBundleCopyInfoDictionaryInDirectory`, with and without a trailing slash on the URL.

Before the fix the file is opened as `Info.plist` after the case-insensitive match found `info.plist`, so the lowercase and uppercase cases return no identifier; after it, all pass.
