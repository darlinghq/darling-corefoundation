# _CFAppVersionCheckLessThan

Build CFAppVersionCheckLessThan.c against CoreFoundation and run it under Darling. It copies itself into three application bundles in a mkdtemp directory under /tmp, runs each copy, and removes the directory.

Checks:
1. A program outside a bundle is never the application asked about.
2. In a bundle with the identifier, the version compared is the leading number of CFBundleShortVersionString (2.5.3 is 2.5), and a version above it gives true.
3. Another identifier, or the same one in other case, gives false.
4. Quirk: any linked-on argument other than -1 gives false.
5. Without a CFBundleShortVersionString (CFBundleVersion is not read), or with one that is not a number, the version is 0.

The behaviour is that of macOS 26.7.3 and Mac OS X 10.14.4. Before the change the function does not exist, and the program fails to link.
