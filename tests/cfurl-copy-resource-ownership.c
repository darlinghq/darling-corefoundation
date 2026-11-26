// CFURLCopyResourcePropertyForKey returns a value the caller owns (the Copy
// rule). The URL's cache keeps its own reference, so after a copy the count
// is two: the cache's and the caller's. CFURLCreateBookmarkData takes its copy
// and gives it back.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Prototype kept for builds against the CF source tree without the CoreFoundation SDK headers.
CF_EXPORT CFIndex CFGetRetainCount(CFTypeRef cf);
CF_EXPORT CFDataRef CFURLCreateBookmarkData(CFAllocatorRef allocator, CFURLRef url, CFURLBookmarkCreationOptions options, CFArrayRef resourcePropertiesToInclude, CFURLRef relativeToURL, CFErrorRef *error);

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static int fatal(const char *what, const char *dir, const char *path)
{
    printf("FAIL %s\n", what);
    unlink(path);
    rmdir(dir);
    return 1;
}

static CFURLRef makeURL(const char *path)
{
    return CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
}

int main(void)
{
    char dir[] = "/tmp/cfurlownership.XXXXXX";
    if (mkdtemp(dir) == NULL) {
        perror("mkdtemp");
        return 2;
    }
    char path[1100];
    snprintf(path, sizeof path, "%s/file.txt", dir);
    FILE *f = fopen(path, "w");
    if (f != NULL)
        fclose(f);

    CFStringRef key = kCFURLContentModificationDateKey;

    CFURLRef url = makeURL(path);
    if (url == NULL)
        return fatal("the file URL is created", dir, path);

    // A value returned by a copy, which the caller must release once.
    CFTypeRef value = NULL;
    Boolean copied = CFURLCopyResourcePropertyForKey(url, key, &value, NULL);
    expect(copied && value != NULL && CFGetTypeID(value) == CFDateGetTypeID(), "the modification date is copied");
    if (!copied || value == NULL) {
        CFRelease(url);
        return fatal("no date to check", dir, path);
    }
    CFAbsoluteTime when = CFDateGetAbsoluteTime((CFDateRef)value);
    CFIndex counted = CFGetRetainCount(value);
    expect(counted == 2, "a copy holds two references: the cache's and the caller's");
    if (counted != 2) {
        // Not released: the caller does not own it here, so releasing would free the cached value.
        return fatal("the copy does not hold a reference of its own", dir, path);
    }

    CFRelease(value);
    value = NULL;
    CFTypeRef again = NULL;
    copied = CFURLCopyResourcePropertyForKey(url, key, &again, NULL);
    expect(copied && again != NULL, "the second copy succeeds");
    expect(again != NULL && CFDateGetAbsoluteTime((CFDateRef)again) == when, "the second copy has the same date");
    expect(again != NULL && CFGetRetainCount(again) == 2, "the second copy holds two references");

    // The authd sequence: the URL goes away, then memory is reused. The caller's
    // reference keeps the date alive.
    CFRelease(url);
    url = NULL;
    CFMutableArrayRef churn = CFArrayCreateMutable(NULL, 4000, &kCFTypeArrayCallBacks);
    for (int i = 0; i < 4000; i++) {
        CFDateRef date = CFDateCreate(NULL, CFAbsoluteTimeGetCurrent() + i);
        CFArrayAppendValue(churn, date);
        CFRelease(date);
    }
    expect(CFDateGetAbsoluteTime((CFDateRef)again) == when, "the date survives the URL and the churn");
    CFRelease(churn);
    CFRelease(again);

    // A NULL out pointer takes no reference and leaves the cached count alone.
    url = makeURL(path);
    if (url == NULL)
        return fatal("the second file URL is created", dir, path);
    CFTypeRef held = NULL;
    copied = CFURLCopyResourcePropertyForKey(url, key, &held, NULL);
    CFIndex before = held != NULL ? CFGetRetainCount(held) : -1;
    expect(copied && before == 2, "the cached date is held once by the cache and once by the caller");
    expect(CFURLCopyResourcePropertyForKey(url, key, NULL, NULL), "a copy with a NULL out pointer succeeds");
    expect(held != NULL && CFGetRetainCount(held) == before, "a NULL out pointer leaves the count unchanged");
    if (held != NULL)
        CFRelease(held);
    CFRelease(url);

    // The bookmark path copies the date (a cache miss on a fresh URL) and must release its copy.
    // Reading the date back afterwards: the cache holds one, the read-back holds one.
    url = makeURL(path);
    if (url == NULL)
        return fatal("the bookmark file URL is created", dir, path);
    const void *keys[1] = { key };
    CFArrayRef requested = CFArrayCreate(NULL, keys, 1, &kCFTypeArrayCallBacks);
    CFErrorRef bookmarkError = NULL;
    CFDataRef bookmark = CFURLCreateBookmarkData(NULL, url, 0, requested, NULL, &bookmarkError);
    expect(bookmark != NULL, "the bookmark is created with the date requested");
    if (bookmark == NULL)
        printf("  bookmark error: %s\n", bookmarkError != NULL ? "set" : "none");
    CFTypeRef readBack = NULL;
    copied = CFURLCopyResourcePropertyForKey(url, key, &readBack, NULL);
    CFIndex readBackCount = readBack != NULL ? CFGetRetainCount(readBack) : -1;
    expect(copied && readBackCount == 2,
           "after the bookmark, the cached date is held by the cache and the read-back only");
    if (readBackCount == 2) {
        CFRelease(readBack);
        expect(CFGetRetainCount(readBack) == 1, "releasing the read-back leaves the cache's reference only");
    }
    if (bookmark != NULL)
        CFRelease(bookmark);
    if (bookmarkError != NULL)
        CFRelease(bookmarkError);
    CFRelease(requested);
    CFRelease(url);

    unlink(path);
    rmdir(dir);
    printf("%s: %d failure(s)\n", failures ? "FAILED" : "OK", failures);
    return failures ? 1 : 0;
}
