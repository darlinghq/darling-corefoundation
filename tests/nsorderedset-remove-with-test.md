# NSMutableOrderedSet removals with a test block

Build `nsorderedset-remove-with-test.m` against Foundation and run it under Darling.

The two tested selectors are internal to this CoreFoundation implementation, but their names and block signatures follow Foundation's block-based filtering pattern. They are expected to enumerate objects (or the supplied indexes) with the documented `NSEnumerationOptions` behavior, collect the objects for which the block returns YES, and remove them after enumeration has finished. The test checks forward and reverse enumeration, removal restricted to a supplied index set, and that setting `*stop` ends enumeration.

Installed baseline: both selectors contain a `DEBUG_BREAK()` and remove nothing; candidate: zero failures.

## Provenance

Behavior follows the public `NSEnumerationOptions` contract and the public block-based filtering APIs such as `-indexesOfObjectsWithOptions:passingTest:` and `-enumerateObjectsWithOptions:usingBlock:`. No application-specific behavior is used. No restricted material was used.
