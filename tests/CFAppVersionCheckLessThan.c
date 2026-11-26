// Copyright (C) 2026 Lubos Dolezel
//
// _CFAppVersionCheckLessThan(bundleID, linkedOnAnOlderSystemThan, version)
// is true when the running application has the bundle identifier and a
// CFBundleShortVersionString below the version. Values are those observed on
// macOS 26.7.3 and Mac OS X 10.14.4, where the program builds and runs too.
//
// The answer depends on the main bundle, so the program runs itself inside
// application bundles it builds in a mkdtemp directory under /tmp, one per
// Info.plist below, and checks what each copy reports.
#include <CoreFoundation/CoreFoundation.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

Boolean _CFAppVersionCheckLessThan(CFStringRef bundleID, int linkedOnAnOlderSystemThan, double versionNumberLessThan);

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

#define ID "org.darlinghq.test.versioncheck"
#define CHECK(version) _CFAppVersionCheckLessThan(CFSTR(ID), -1, version)

// What each bundle's copy checks, chosen by the bundle's CFBundleName.
static void checkInBundle(const char *name)
{
    if (strcmp(name, "dotted") == 0) {
        // CFBundleShortVersionString 2.5.3, CFBundleVersion 1
        expect(CHECK(2.51) && CHECK(3) && CHECK(100), "a version below the one asked about");
        expect(!CHECK(2.5) && !CHECK(2.4) && !CHECK(1),
               "the leading number of the short version string (2.5.3 is 2.5)");
        expect(!_CFAppVersionCheckLessThan(CFSTR("org.darlinghq.test.other"), -1, 100),
               "another application is not this one");
        expect(!_CFAppVersionCheckLessThan(CFSTR("ORG.DARLINGHQ.TEST.VERSIONCHECK"), -1, 100),
               "the identifier is compared with case");
        expect(!_CFAppVersionCheckLessThan(CFSTR(ID), 0, 100) && !_CFAppVersionCheckLessThan(CFSTR(ID), 1, 100)
                       && !_CFAppVersionCheckLessThan(CFSTR(ID), 100000, 100),
               "quirk: a linked-on condition is never met");
    } else if (strcmp(name, "bundleversion") == 0) {
        // no CFBundleShortVersionString, CFBundleVersion 2.5
        expect(CHECK(0.5) && CHECK(1), "without a short version string the version is 0");
    } else if (strcmp(name, "text") == 0) {
        // CFBundleShortVersionString "abc"
        expect(CHECK(0.5), "a short version string that is not a number is 0");
        expect(!CHECK(0), "0 is not below 0");
    } else {
        expect(0, "a known bundle");
    }
}

static int runInBundle(const char *dir, const char *self, const char *name, const char *keys)
{
    char path[1200], command[2600];
    snprintf(path, sizeof path, "%s/%s.app/Contents/MacOS", dir, name);
    snprintf(command, sizeof command, "mkdir -p '%s' && cp '%s' '%s/versioncheck'", path, self, path);
    if (system(command) != 0)
        return 1;

    snprintf(path, sizeof path, "%s/%s.app/Contents/Info.plist", dir, name);
    FILE *plist = fopen(path, "w");
    if (plist == NULL)
        return 1;
    fprintf(plist,
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<plist version=\"1.0\"><dict>\n"
            "<key>CFBundleIdentifier</key><string>" ID "</string>\n"
            "<key>CFBundleExecutable</key><string>versioncheck</string>\n"
            "<key>CFBundleName</key><string>%s</string>\n%s"
            "</dict></plist>\n",
            name, keys);
    fclose(plist);

    snprintf(path, sizeof path, "%s/%s.app/Contents/MacOS/versioncheck", dir, name);
    fflush(stdout);
    pid_t child = fork();
    if (child == 0) {
        execl(path, path, "--in-bundle", (char *) NULL);
        _exit(127);
    }
    int status = 0;
    waitpid(child, &status, 0);
    return !WIFEXITED(status) || WEXITSTATUS(status) != 0;
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "--in-bundle") == 0) {
        CFStringRef name = CFBundleGetValueForInfoDictionaryKey(CFBundleGetMainBundle(), kCFBundleNameKey);
        char text[64] = "";
        if (name != NULL)
            CFStringGetCString(name, text, sizeof text, kCFStringEncodingUTF8);
        checkInBundle(text);
        return failures != 0;
    }

    expect(!CHECK(100), "a program outside a bundle is no application");

    char self[1024];
    uint32_t size = sizeof self;
    char dir[] = "/tmp/cfversioncheck.XXXXXX";
    if (_NSGetExecutablePath(self, &size) != 0 || mkdtemp(dir) == NULL) {
        perror("setup");
        return 1;
    }
    int bad = 0;
    bad |= runInBundle(dir, self, "dotted",
                       "<key>CFBundleShortVersionString</key><string>2.5.3</string>\n"
                       "<key>CFBundleVersion</key><string>1</string>\n");
    bad |= runInBundle(dir, self, "bundleversion", "<key>CFBundleVersion</key><string>2.5</string>\n");
    bad |= runInBundle(dir, self, "text", "<key>CFBundleShortVersionString</key><string>abc</string>\n");

    char command[100];
    snprintf(command, sizeof command, "rm -rf '%s'", dir);
    system(command);

    if (bad)
        failures++;
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
