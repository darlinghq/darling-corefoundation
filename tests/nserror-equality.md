# NSError equality

Build nserror-equality.m against Foundation and run it under Darling (or on macOS, where it passes). It compares errors by domain, code and user info, treats a missing user info as an empty one, and checks that equal errors hash alike.

Installed baseline: equal errors compare unequal and hash differently (NSError used identity comparison); candidate: all checks pass.
