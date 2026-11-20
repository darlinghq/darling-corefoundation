# Plural rule strings from .stringsdict tables

Build StringsDictPluralFormat.m against Foundation and run it under Darling. It
creates two bundles in its own mkdtemp directory under /tmp and removes them.

Checks:
1. `-[NSBundle localizedStringForKey:value:table:]` and `CFBundleCopyLocalizedString`
   return the NSStringLocalizedFormatKey value of a .stringsdict entry; an entry of
   the .stringsdict wins over a .strings entry with the same key, and plain string
   entries are returned as they are.
2. Formatting such a string (`-initWithFormat:locale:`, `+localizedStringWithFormat:`,
   `+stringWithFormat:`, `-appendFormat:`, `CFStringCreateWithFormat`) expands each
   `%#@variable@` with the format of the argument's plural category, formatted with
   the arguments from that one on; copies and mutable copies keep the entry.
3. The plural rules are those of the locale passed in (French: 0 is "one"), and
   English ones when no locale is passed (quirk), whatever localization the string
   came from.
4. A "zero" format is used for 0 even in English (quirk).

The test passes on macOS 26.7.3 and on Mac OS X 10.14.4 (also with
`-AppleLocale fr_FR`). Darling before the change returns the keys (27 checks
fail); after it every check passes on x86_64 and i386.
