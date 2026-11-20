# CFURLEnumerator URL ownership

Build CFURLEnumeratorGetRule.c against CoreFoundation and run it under Darling. It creates and removes its own mkdtemp directory under /tmp.

Checks:
1. Every URL that `CFURLEnumeratorGetNextURL` returns follows the Get rule: once the caller has retained each one and released the enumerator, one reference is left.
2. A returned URL is valid until the next call.
3. Enumerating without a URL out-parameter still returns every entry.

The behaviour is that of macOS 26.7.3 and Mac OS X 10.14.4. Before the change each URL keeps an extra reference (a leak); after it all checks pass.
