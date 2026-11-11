# CFCGTypes in the CoreFoundation umbrella

`cfcgtypes.c` includes only `<CoreFoundation/CoreFoundation.h>` and checks that
`CGFloat`, `CGPoint`, `CGSize`, `CGVector` and `CGRect` are usable with the
expected sizes, and that `CFStringTokenizerCreate` is declared. It prints
`PASS` on success. Without the CFCGTypes.h export the build fails with
unknown type names.
