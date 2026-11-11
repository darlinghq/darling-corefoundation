# Localized strings from .loctable tables

Build BundleLocTable.m against Foundation/CoreFoundation and run under Darling. It creates a temporary bundle with `Localizable.loctable` (en and de tables, one plural-style dictionary entry) and an `Other` table present both as `en.lproj/Other.strings` and `Other.loctable`, then checks default-language, explicit-localization, missing-key, non-string-entry, `.loctable`-over-`.strings` precedence (a QUIRK), missing-table and `NSBundle` lookups.

Without the fix every `.loctable` lookup returns its key; with it there are no failures.
