# URL component character sets

Build `url-character-sets.m` as an Objective-C executable linked to Foundation
and run it with the candidate CoreFoundation framework. Assertions are kept
enabled even with an `NDEBUG` build. Success prints:

```
PASS: six URL character sets, ASCII membership and independent mutable copies
```

The test checks selector availability, all 128 ASCII characters for each of
the six component sets, representative non-ASCII exclusions, repeated-call
identity and mutation of an independent copy. Expected membership is expressed
as the common unreserved set plus each component's delimiters, independently
of the implementation's sorted strings.

The implementation follows the character lists in the pinned open-source
`submodules/swift-corelibs-foundation/CoreFoundation/URL.subproj/CFURLComponents_URIParser.c`.
Notable distinctions include brackets in the host set, no semicolon in the path
set, and slash/question mark in the query and fragment sets. These APIs describe
whole URL components; a query's allowed set is not a query-value escaping policy.

Validation: all 131 candidate CoreFoundation translation units were rebuilt
and linked using the staged ARM64 build's recipes and dependencies. The probe
passed in a disposable Darling guest with that framework substituted. With the
unmodified staged framework it failed the first selector-availability assertion.
Upstream source at `855b8e944836a5a28864634e18dd87af22dd9b82` also lacks these methods.
This is not a clean rebuild of every Darling dependency, native macOS parity
testing, or x86 runtime validation. The guest reports a pre-existing duplicate
NSPort class between the rebuilt CoreFoundation and staged Foundation.
