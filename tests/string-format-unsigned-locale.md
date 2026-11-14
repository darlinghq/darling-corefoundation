# CFString unsigned formats with a locale

Build string-format-unsigned-locale.c against CoreFoundation and run it under Darling (it also passes on macOS 26.7.3). It formats %llu/%lu/%u/%hu/%hhu with an en_US locale as format options and without one.

Installed baseline: "llu UINT64_MAX" and the other values above INT64_MAX fail (printed as -1 etc. with grouping); candidate: all checks pass. The `quirk` cases pin the sign extension of narrow unsigned conversions.
