# NSTimeZone localTimeZone

Build nstimezone-local-timezone.m against Foundation and run it under Darling twice: without arguments (TZ unset) and with `tz` (TZ=Europe/Berlin). Both must print PASS.

Before the fix the TZ-unset run crashes in the first +localTimeZone call (the variable's NULL value is passed to CFStringCreateWithCString); the `tz` run passes either way.
