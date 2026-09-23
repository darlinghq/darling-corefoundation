# Localized strings from .loctable tables

Build BundleLocTable.m against Foundation/CoreFoundation and run under Darling. It creates a temporary bundle with `Localizable.loctable` (en and de tables, one plural-style dictionary entry) and an `Other` table present both as `en.lproj/Other.strings` and `Other.loctable`, then checks default-language, explicit-localization, missing-key, non-string-entry, `.strings`-precedence and `NSBundle` lookups.

Baseline: three failures (every `.loctable` lookup returns its key); candidate: zero failures.
