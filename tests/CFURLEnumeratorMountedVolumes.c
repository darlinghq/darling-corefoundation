// Copyright (C) 2026 Lubos Dolezel
//
// CFURLEnumeratorCreateForMountedVolumes lists the mount points of the mount table as directory URLs, in table
// order, without the device file system; kCFURLEnumeratorSkipInvisibles leaves out the volumes the system marks as
// not to be browsed. Behaviour observed on macOS 26.7.3 and Mac OS X 10.14.4 (probe:
// mac-probes/gog-blockers/cf-resourcemap-volumes.c); the program builds and runs there too.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static int countVolumes(CFURLEnumeratorOptions options, CFArrayRef keys, int *sawRoot, CFErrorRef *error, CFURLEnumeratorResult *last)
{
    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForMountedVolumes(NULL, options, keys);
    if (enumerator == NULL)
        return -1;
    int count = 0;
    CFURLRef url;
    CFURLEnumeratorResult result;
    *sawRoot = 0;
    while ((result = CFURLEnumeratorGetNextURL(enumerator, &url, error)) == kCFURLEnumeratorSuccess) {
        char path[1024];
        if (CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path) && strcmp(path, "/") == 0)
            *sawRoot = 1;
        count++;
    }
    *last = result;
    expect(CFURLEnumeratorGetDescendentLevel(enumerator) == 0, "a volume enumerator has no descendent level");
    expect(!CFURLEnumeratorGetSourceDidChange(enumerator), "the source did not change");
    CFRelease(enumerator);
    return count;
}

int main(void)
{
    CFErrorRef error = NULL;
    CFURLEnumeratorResult last;
    int root;
    int all = countVolumes(kCFURLEnumeratorDefaultBehavior, NULL, &root, &error, &last);
    expect(all >= 1, "at least one volume is listed");
    expect(root, "the root file system is among the volumes");
    expect(last == kCFURLEnumeratorEnd && error == NULL, "the list ends with kCFURLEnumeratorEnd and no error");

    int visible = countVolumes(kCFURLEnumeratorSkipInvisibles, NULL, &root, &error, &last);
    expect(visible >= 1 && visible <= all, "skipping the invisible volumes leaves a subset");
    expect(root, "the root file system is visible");

    // every mount point of the table except the device file system, none twice-skipped
    int expected = 0;
    int n = getfsstat(NULL, 0, MNT_NOWAIT);
    struct statfs mounts[512];
    if (n > 512)
        n = 512;
    n = getfsstat(mounts, (int)sizeof(mounts), MNT_NOWAIT);
    for (int i = 0; i < n; i++)
        if (strcmp(mounts[i].f_fstypename, "devfs") != 0)
            expected++;
    // macOS 26 also leaves out the data volume of the system (a "root data" mount), so one entry may be missing.
    expect(all <= expected && all >= expected - 1, "the volumes are the mount table entries except devfs");

    // with property keys the enumeration still lists the volumes
    CFStringRef key = kCFURLNameKey;
    CFArrayRef keys = CFArrayCreate(NULL, (const void **)&key, 1, &kCFTypeArrayCallBacks);
    int withKeys = countVolumes(kCFURLEnumeratorDefaultBehavior, keys, &root, &error, &last);
    CFRelease(keys);
    expect(withKeys == all, "property keys do not change what is listed");

    // the option to descend does not apply to volumes
    int recursive = countVolumes(kCFURLEnumeratorDescendRecursively, NULL, &root, &error, &last);
    expect(recursive == all, "descending recursively lists the same volumes");

    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForMountedVolumes(NULL, 0, NULL);
    CFURLRef url = NULL;
    CFURLEnumeratorGetNextURL(enumerator, &url, NULL);
    expect(url != NULL && CFURLHasDirectoryPath(url), "a volume URL is a directory URL");
    CFURLEnumeratorSkipDescendents(enumerator);
    CFRelease(enumerator);

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
