# Current locale and the AppleLocale preference

`locale-applelocale-pref.c` checks that the current locale follows the `AppleLocale` application preference, ignores `LC_ALL` when the preference is unset, and that metric-system queries on locales with and without preferences do not crash. It prints `N/N passed`.

Before the change `AppleLocale` was ignored (the code was disabled), so the fr_FR and ja_JP checks fail; the preference-less locale check covers the NULL `_prefs` guard.
