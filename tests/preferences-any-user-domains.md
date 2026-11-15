# Any-user preference domains

`preferences-any-user-domains.c` checks that the any-user domains (`kCFPreferencesAnyUser`) are stored in `/Library/Preferences/<domain>.plist` for both `kCFPreferencesAnyHost` and `kCFPreferencesCurrentHost`, and that both host selectors reach the same domain: the global domain's key lists are equal, and a value written through one selector is read through the other. The write part prints `SKIP` when `/Library/Preferences` is not writable. It prints `PASS` or `FAIL`.

macOS 26.7.3 (read-only probe through CFPreferencesCopyKeyList/CopyValue): for the global domain and for com.apple.loginwindow, com.apple.TimeMachine and com.apple.PowerManagement, AnyUser with AnyHost and AnyUser with CurrentHost return the same keys, from `/Library/Preferences`. Before the change the AnyHost variant read `/Library/Preferences/Network/`, so the system-wide global domain was not found with `(AnyApplication, AnyUser, AnyHost)`.
