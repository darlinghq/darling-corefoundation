# Third-party notices

## swift-corelibs-foundation

The ICU pattern builder for `CFDateFormatterCreateISO8601Formatter`
(`__CFDateFormatterCreateISO8601Pattern` in `CFDateFormatter.c`) follows the
structure of `__createISO8601FormatString` in swift-corelibs-foundation.

- Source: https://github.com/swiftlang/swift-corelibs-foundation
- License: Apache License 2.0 with Runtime Library Exception
- Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors

## swift-corelibs-foundation (CFURLComponents)

`CFURLComponents.c`, `CFURLComponents_URIParser.c`, `CFURLComponents.h`,
`CFURLComponents_Internal.h` and `CFOverflow.h` are compiled unmodified from the
`submodules/swift-corelibs-foundation` checkout (Darling's fork of
https://github.com/swiftlang/swift-corelibs-foundation).

- Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
- Licensed under the Apache License v2.0 with Runtime Library Exception
- License: https://swift.org/LICENSE.txt
- Contributors: https://swift.org/CONTRIBUTORS.txt

The notices in each source file are kept as they are. `cfurlcomponents-shim/`
contains only Darling's own glue (a runtime header and the class
registration call).
