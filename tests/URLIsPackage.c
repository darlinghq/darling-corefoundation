// Copyright (C) 2026 Lubos Dolezel
//
// kCFURLIsPackageKey and kCFURLEnumeratorSkipPackageContents in a program
// that links only CoreFoundation. A directory is a package when its type is
// declared as one (.app, .bundle, .plugin, .rtfd, .pages) or when it has the
// Finder's bundle bit; a .framework, a plain folder, a file and a symbolic
// link are not. The expected values are those observed on macOS 26.7.3 and
// Mac OS X 10.14.4 (x86_64 and i386), where the program builds and runs too.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

static int failures;
static char root[PATH_MAX];

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static void makeDirectory(const char *rel)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/%s", root, rel);
    mkdir(path, 0755);
}

static void makeFile(const char *rel)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/%s", root, rel);
    FILE *f = fopen(path, "w");
    if (f != NULL)
        fclose(f);
}

static void makeLink(const char *target, const char *rel)
{
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/%s", root, rel);
    symlink(target, path);
}

// Sets kHasBundle (0x2000) in the Finder flags, bytes 8 and 9 (big endian)
// of the 32-byte com.apple.FinderInfo attribute.
static int setBundleBit(const char *rel)
{
    char path[PATH_MAX];
    unsigned char info[32] = { 0 };
    snprintf(path, sizeof path, "%s/%s", root, rel);
    info[8] = 0x20;
    return setxattr(path, "com.apple.FinderInfo", info, sizeof info, 0, 0);
}

static void removeTree(const char *path)
{
    struct stat info;
    if (lstat(path, &info) != 0)
        return;
    if (S_ISDIR(info.st_mode)) {
        DIR *dir = opendir(path);
        struct dirent *entry;
        while (dir != NULL && (entry = readdir(dir)) != NULL) {
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
                continue;
            char child[PATH_MAX];
            snprintf(child, sizeof child, "%s/%s", path, entry->d_name);
            removeTree(child);
        }
        if (dir != NULL)
            closedir(dir);
        rmdir(path);
    } else {
        unlink(path);
    }
}

// An empty name is the test directory itself.
static CFURLRef createURL(const char *rel)
{
    char path[PATH_MAX];
    struct stat info;
    snprintf(path, sizeof path, *rel ? "%s/%s" : "%s", root, rel);
    Boolean isDirectory = lstat(path, &info) == 0 && S_ISDIR(info.st_mode);
    return CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), isDirectory);
}

// 1 or 0 for a CFBoolean, -1 when no value came back.
static int isPackage(const char *rel, Boolean *succeeded)
{
    CFURLRef url = createURL(rel);
    CFTypeRef value = NULL;
    CFErrorRef error = NULL;
    *succeeded = CFURLCopyResourcePropertyForKey(url, kCFURLIsPackageKey, &value, &error);
    int result = -1;
    if (value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID())
        result = CFBooleanGetValue(value) ? 1 : 0;
    if (value != NULL)
        CFRelease(value);
    if (error != NULL)
        CFRelease(error);
    CFRelease(url);
    return result;
}

static void checkPackage(const char *rel, int expected)
{
    Boolean succeeded = false;
    char what[256];
    int value = isPackage(rel, &succeeded);
    snprintf(what, sizeof what, "%s: kCFURLIsPackageKey is %s (got %d)", rel, expected ? "true" : "false", value);
    expect(succeeded && value == expected, what);
}

enum { MaxSeen = 64 };
static char *seen[MaxSeen];
static int seenCount;

static void enumerate(const char *rel, CFURLEnumeratorOptions options)
{
    for (int i = 0; i < seenCount; i++)
        free(seen[i]);
    seenCount = 0;

    CFURLRef directory = createURL(rel);
    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForDirectoryURL(NULL, directory, options, NULL);
    CFURLRef url = NULL;
    CFErrorRef error = NULL;
    CFURLEnumeratorResult result;
    size_t rootLength = strlen(root);

    while (enumerator != NULL && (result = CFURLEnumeratorGetNextURL(enumerator, &url, &error)) != kCFURLEnumeratorEnd) {
        if (result == kCFURLEnumeratorSuccess && seenCount < MaxSeen) {
            char path[PATH_MAX];
            if (CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path) && strncmp(path, root, rootLength) == 0)
                seen[seenCount++] = strdup(path + rootLength + 1);
        }
        if (error != NULL) {
            CFRelease(error);
            error = NULL;
        }
    }
    if (enumerator != NULL)
        CFRelease(enumerator);
    CFRelease(directory);
}

static int wasSeen(const char *rel)
{
    for (int i = 0; i < seenCount; i++)
        if (strcmp(seen[i], rel) == 0)
            return 1;
    return 0;
}

static void checkSeen(const char *rel, int expected, const char *context)
{
    char what[256];
    snprintf(what, sizeof what, "%s: %s is %s", context, rel, expected ? "listed" : "skipped");
    expect(wasSeen(rel) == expected, what);
}

int main(void)
{
    char dir[] = "/tmp/cfurlpackage.XXXXXX";
    if (mkdtemp(dir) == NULL) {
        perror("mkdtemp");
        return 1;
    }
    // Compare against the resolved path; /tmp is a link on macOS.
    if (realpath(dir, root) == NULL) {
        perror("realpath");
        return 1;
    }

    makeDirectory("App.app");
    makeDirectory("App.app/Contents");
    makeFile("App.app/Contents/Info.plist");
    makeDirectory("Plain.app");
    makeFile("Plain.app/inner");
    makeDirectory("Upper.APP");
    makeDirectory("Thing.bundle");
    makeFile("Thing.bundle/inner");
    makeDirectory("Ext.plugin");
    makeDirectory("Doc.rtfd");
    makeFile("Doc.rtfd/TXT.rtf");
    makeDirectory("Doc.pages");
    makeDirectory("Kit.framework");
    makeFile("Kit.framework/inner");
    makeDirectory("Folder");
    makeDirectory("Folder/sub");
    makeFile("Folder/sub/file");
    makeDirectory("Bit");
    makeFile("Bit/inner");
    makeFile("file.app");
    makeLink("App.app", "LinkApp.app");
    makeLink("Bit", "LinkBit");

    expect(setBundleBit("Bit") == 0, "the bundle bit can be set on a directory");

    checkPackage("App.app", 1);
    checkPackage("Plain.app", 1); // no Info.plist: the extension alone decides
    checkPackage("Upper.APP", 1);
    checkPackage("Thing.bundle", 1);
    checkPackage("Ext.plugin", 1);
    checkPackage("Doc.rtfd", 1);
    checkPackage("Doc.pages", 1);
    checkPackage("Kit.framework", 0);
    checkPackage("Folder", 0);
    checkPackage("Bit", 1);
    checkPackage("file.app", 0);
    checkPackage("LinkApp.app", 0);
    checkPackage("LinkBit", 0);

    Boolean succeeded = true;
    int missing = isPackage("Missing.app", &succeeded);
    expect(!succeeded && missing == -1, "Missing.app: no value and an error");

    const char *context = "recursive, skipping package contents";
    enumerate("", kCFURLEnumeratorDescendRecursively | kCFURLEnumeratorSkipPackageContents);
    checkSeen("App.app", 1, context);
    checkSeen("App.app/Contents", 0, context);
    checkSeen("Plain.app/inner", 0, context);
    checkSeen("Thing.bundle/inner", 0, context);
    checkSeen("Doc.rtfd", 1, context);
    checkSeen("Doc.rtfd/TXT.rtf", 0, context);
    checkSeen("Bit", 1, context);
    checkSeen("Bit/inner", 0, context);
    checkSeen("Kit.framework/inner", 1, context);
    checkSeen("Folder/sub/file", 1, context);
    checkSeen("LinkApp.app", 1, context);

    context = "recursive";
    enumerate("", kCFURLEnumeratorDescendRecursively);
    checkSeen("App.app/Contents/Info.plist", 1, context);
    checkSeen("Bit/inner", 1, context);
    checkSeen("Doc.rtfd/TXT.rtf", 1, context);

    context = "rooted at a package, skipping package contents";
    enumerate("App.app", kCFURLEnumeratorDescendRecursively | kCFURLEnumeratorSkipPackageContents);
    checkSeen("App.app/Contents", 1, context);
    checkSeen("App.app/Contents/Info.plist", 1, context);

    removeTree(root);

    printf("%s\n", failures == 0 ? "ALL PASS" : "SOME FAILED");
    return failures == 0 ? 0 : 1;
}
