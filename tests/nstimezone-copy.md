# NSTimeZone copy

Build nstimezone-copy.m against Foundation and run it under Darling (or on macOS, where it passes). It copies a named and a fixed-offset time zone and uses a time zone as a dictionary key; copying must not raise and must return the same immutable object.

Installed baseline: the first -copy raises (-copyWithZone: unimplemented); candidate: all checks pass.
