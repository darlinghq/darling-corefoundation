/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CFBundleCopyInfoDictionaryInDirectory finds the Info.plist by a
 * case-insensitive match of the file name, so the file must then be opened
 * under the name that was found, in every bundle layout.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int failures;

static void makeDir(const char *path) {
    if (mkdir(path, 0700) != 0) { perror(path); exit(2); }
}

static void writeFile(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(2); }
    fputs(text, f);
    fclose(f);
}

static void check(const char *label, const char *bundlePath, const char *expectedId, Boolean directoryURL) {
    CFStringRef p = CFStringCreateWithCString(NULL, bundlePath, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, p, kCFURLPOSIXPathStyle, directoryURL);
    CFDictionaryRef info = CFBundleCopyInfoDictionaryInDirectory(url);
    CFStringRef id = info ? CFDictionaryGetValue(info, CFSTR("CFBundleIdentifier")) : NULL;
    char buf[128] = "";
    if (id) CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8);
    int ok = id && strcmp(buf, expectedId) == 0;
    printf("%s %s: identifier \"%s\"\n", ok ? "PASS" : "FAIL", label, buf);
    failures += !ok;
    if (info) CFRelease(info);
    CFRelease(url);
    CFRelease(p);
}

static const char *plist(const char *id) {
    static char buf[512];
    snprintf(buf, sizeof buf, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>"
             "<key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n", id);
    return buf;
}

int main(void) {
    char root[] = "/tmp/darling-infoplist-XXXXXX";
    if (!mkdtemp(root)) return 2;
    char path[1024], path2[1024];

    snprintf(path, sizeof path, "%s/Lower.bundle", root);           makeDir(path);
    snprintf(path, sizeof path, "%s/Lower.bundle/Contents", root);  makeDir(path);
    snprintf(path, sizeof path, "%s/Lower.bundle/Contents/info.plist", root);
    writeFile(path, plist("org.darlinghq.lower-contents"));

    snprintf(path, sizeof path, "%s/Flat.bundle", root);            makeDir(path);
    snprintf(path, sizeof path, "%s/Flat.bundle/INFO.PLIST", root);
    writeFile(path, plist("org.darlinghq.upper-flat"));

    snprintf(path, sizeof path, "%s/Normal.bundle", root);          makeDir(path);
    snprintf(path, sizeof path, "%s/Normal.bundle/Contents", root); makeDir(path);
    snprintf(path, sizeof path, "%s/Normal.bundle/Contents/Info.plist", root);
    writeFile(path, plist("org.darlinghq.normal"));

    snprintf(path, sizeof path, "%s/Lower.bundle", root);
    check("lowercase info.plist in Contents", path, "org.darlinghq.lower-contents", true);
    check("lowercase info.plist, URL without trailing slash", path, "org.darlinghq.lower-contents", false);
    snprintf(path, sizeof path, "%s/Flat.bundle", root);
    check("INFO.PLIST in a flat bundle", path, "org.darlinghq.upper-flat", true);
    snprintf(path, sizeof path, "%s/Normal.bundle", root);
    check("Info.plist in Contents", path, "org.darlinghq.normal", true);
    check("Info.plist, URL without trailing slash", path, "org.darlinghq.normal", false);

    snprintf(path2, sizeof path2, "rm -rf '%s'", root);
    if (system(path2) != 0) return 2;
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
