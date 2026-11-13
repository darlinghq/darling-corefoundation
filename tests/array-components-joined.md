# NSArray componentsJoinedByString:

Build array-components-joined.m against Foundation/CoreFoundation (ARC or MRC) and run it under Darling. It joins arrays whose elements include the same object more than once (repeated string literals, as the first, middle or last element) and checks that the separator appears between every pair of adjacent elements, plus the empty array, a single element, an empty separator, a mutable array, non-string elements and the exception for a separator that is not a string.

Installed baseline: the cases with a repeated last element fail (the separator is missing before every element that is the same object as the last one); candidate: zero failures.
