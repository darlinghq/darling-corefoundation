// Copyright (C) 2026 Lubos Dolezel
//
// CFURLEnumeratorGetNextURL returns its URL under the Get rule: the enumerator
// keeps the URL until the next call or until it is released, and the caller
// retains it to keep it longer. The error it returns is the caller's to
// release. Values are those observed on macOS 26.7.3 and Mac OS X 10.14.4,
// where the program builds and runs too.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static void touch(const char *dir, const char *name)
{
    char path[1100];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "w");
    if (f != NULL)
        fclose(f);
}

enum { MaxURLs = 16 };

int main(void)
{
    char dir[] = "/tmp/cfurlenum.XXXXXX";
    if (mkdtemp(dir) == NULL) {
        perror("mkdtemp");
        return 2;
    }
    char sub[1100];
    snprintf(sub, sizeof sub, "%s/sub", dir);
    mkdir(sub, 0755);
    touch(dir, "a.txt");
    touch(dir, "b.txt");
    touch(sub, "c.txt");

    CFURLRef dirURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)dir, strlen(dir), true);

    // Every URL returned, retained here and then checked once the enumerator
    // is gone: only this reference may be left.
    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForDirectoryURL(NULL, dirURL,
            kCFURLEnumeratorDescendRecursively, NULL);
    expect(enumerator != NULL, "the enumerator is created");
    CFURLRef urls[MaxURLs];
    CFIndex heldByEnumerator[MaxURLs];
    int count = 0;
    CFURLRef url = NULL;
    CFErrorRef error = NULL;
    while (enumerator != NULL && CFURLEnumeratorGetNextURL(enumerator, &url, &error) == kCFURLEnumeratorSuccess) {
        if (url != NULL && count < MaxURLs) {
            heldByEnumerator[count] = CFGetRetainCount(url);
            urls[count++] = (CFURLRef)CFRetain(url);
        }
    }
    expect(count == 4, "four URLs are returned");
    int valid = 1;
    for (int i = 0; i < count; i++)
        valid &= heldByEnumerator[i] >= 1;
    expect(valid, "a returned URL is valid until the next call");
    if (enumerator != NULL)
        CFRelease(enumerator);

    int owned = 1;
    for (int i = 0; i < count; i++) {
        CFIndex left = CFGetRetainCount(urls[i]);
        if (left != 1) {
            printf("  URL %d has %ld references left, 1 expected\n", i, (long)left);
            owned = 0;
        }
        CFRelease(urls[i]);
    }
    expect(owned, "the enumerator gives up the URLs it returned when it is released");

    // Without a URL out-parameter the enumeration still walks the tree.
    enumerator = CFURLEnumeratorCreateForDirectoryURL(NULL, dirURL, kCFURLEnumeratorDescendRecursively, NULL);
    int walked = 0;
    while (enumerator != NULL && CFURLEnumeratorGetNextURL(enumerator, NULL, NULL) == kCFURLEnumeratorSuccess)
        walked++;
    expect(walked == 4, "the enumeration without a URL out-parameter returns four results");
    if (enumerator != NULL)
        CFRelease(enumerator);

    CFRelease(dirURL);
    char path[1100];
    snprintf(path, sizeof path, "%s/c.txt", sub);
    unlink(path);
    rmdir(sub);
    snprintf(path, sizeof path, "%s/a.txt", dir);
    unlink(path);
    snprintf(path, sizeof path, "%s/b.txt", dir);
    unlink(path);
    rmdir(dir);

    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
