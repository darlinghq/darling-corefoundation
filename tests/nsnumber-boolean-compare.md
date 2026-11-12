# NSNumber compared with booleans

Build nsnumber-boolean-compare.m against Foundation and run it under Darling (or on macOS, where it passes). It compares numbers of every storage kind, numbers decoded by NSUnarchiver and NSKeyedUnarchiver, and array and dictionary elements with @YES and @NO using -isEqual:, -isEqualToNumber: and -compare: in both directions.

Installed baseline: crashes at the first comparison of a non-boolean number with a boolean (CFNumberCompare asserts on the CFBoolean); candidate: all checks pass.
