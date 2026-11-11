# CFURLEnumerator Recursion and NULL Parameter Handling

Test `CFURLEnumerator` directory recursion and NULL parameter safety.

Checks:
1. `kCFURLEnumeratorDefaultBehavior` stays flat and does not descend into subdirectories.
2. `kCFURLEnumeratorDescendRecursively` recursively visits nested directories and files.
3. Passing `url == NULL` to `CFURLEnumeratorGetNextURL` successfully iterates through directories without dereferencing a NULL pointer in `CFURLEnumeratorPushURL` or leaking memory.
4. Passing `url == NULL` with `propertyKeys` requested successfully queries resource properties for all entries without dereferencing a NULL pointer in `CFURLCopyResourcePropertiesForKeys`.
5. `CFURLEnumeratorSkipDescendents` skips descending into the specified directory during recursive traversal.
