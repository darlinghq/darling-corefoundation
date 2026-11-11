# NSMutableArray removeObjectsInRange:

Build MutableArrayRemoveRange.m against Foundation/CoreFoundation (manual retain/release) and run it under Darling. Thirteen checks: ranges at the start, middle and end, the whole array, single elements, empty ranges at every edge and on an empty array, and NSRangeException without modifying the array for a range past the end, a location past the end, and a length whose NSMaxRange wraps.

Installed baseline: six failures ("index (-1) beyond array bounds" for every range starting at 0, and no exception for location 6 of 5); candidate: zero failures.
