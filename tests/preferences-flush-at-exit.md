# Preferences set without a synchronize call survive the process

Build `preferences-flush-at-exit.m` with Foundation and run it under Darling (`DISPLAY` not needed). It starts itself as children that set preferences (`CFPreferencesSetAppValue`, `-[NSUserDefaults setObject:forKey:]`, one overwriting a key of an existing preferences file) and exit without synchronizing, once by returning from `main` and once by `exit()`, then reads the preferences file and the values in a third child.

Before the fix the values were only written by an explicit synchronize or by the 30 second timer of `NSUserDefaults`, so a process that exited sooner lost them (the preferences file kept the old values); after it, the exit handler writes them and all checks pass.
