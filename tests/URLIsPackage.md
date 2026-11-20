# kCFURLIsPackageKey and skipping package contents

Build URLIsPackage.c against CoreFoundation only and run it under Darling. It creates and removes its own mkdtemp directory under /tmp.

Checks:
1. `kCFURLIsPackageKey` is true for directories whose type is a package (`.app` with or without an Info.plist, `.APP`, `.bundle`, `.plugin`, `.rtfd`, `.pages`) and for a plain directory with the Finder's bundle bit; false for a `.framework`, a plain folder, a file named `.app` and symbolic links to packages; a missing item gives no value and an error.
2. `kCFURLEnumeratorSkipPackageContents` lists each package but not its contents, and still descends into other directories; a package that is the enumeration root is enumerated.

The behaviour is that of macOS 26.7.3 and Mac OS X 10.14.4 (x86_64 and i386). The type answers come from LaunchServices, which CoreFoundation loads for the first package question, as macOS does. Before the change the key has no value and the enumerator descends into packages; after it all checks pass.
