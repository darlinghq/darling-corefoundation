# System time zone through a chain of links

`timezone-system-link.c` follows `/etc/localtime` link by link to the first target with a `zoneinfo` directory component and takes the path below it as the expected zone name, and checks that `CFTimeZoneCopySystem()` has that name (after removing TZ and TZFILE from the environment). It prints `PASS` or `FAIL`, and `SKIP` when `/etc/localtime` is missing or does not lead to a zoneinfo file.

Under Darling `/etc/localtime` is a link into the host's file system (`/Volumes/SystemRoot/etc/localtime`), which is itself a link to the host's zone file. Before the change the first link's target was taken as the zone name, no zone of that name exists, and the system time zone became GMT.
