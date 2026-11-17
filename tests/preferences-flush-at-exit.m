// Copyright (C) 2026 Lubos Dolezel
//
// A preference set with CFPreferencesSetAppValue(), or -[NSUserDefaults setObject:forKey:], is stored for the
// application even when the process exits without anything synchronizing it: the value is in the application's
// preferences file after the process has exited normally, and the next process reads it. The test starts itself as
// a child that sets values and exits (by returning from main, and by calling exit()), then reads the file and the
// values in a second child.
#import <Foundation/Foundation.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

extern char **environ;

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static int run(const char *self, const char *mode) {
    char *argv[] = { (char *) self, (char *) mode, NULL };
    pid_t pid;
    int status = -1;
    if (posix_spawn(&pid, self, NULL, NULL, argv, environ) != 0)
        return -1;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static NSString *preferencesFile(void) {
    return [NSHomeDirectory() stringByAppendingFormat: @"/Library/Preferences/%@.plist",
            [[NSProcessInfo processInfo] processName]];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "set-cf")) {
            CFPreferencesSetAppValue(CFSTR("flushCF"), CFSTR("cf-value"), kCFPreferencesCurrentApplication);
            return 0; // no synchronize call
        }
        if (argc > 1 && !strcmp(argv[1], "set-defaults")) {
            [[NSUserDefaults standardUserDefaults] setInteger: 2 forKey: @"flushDefaults"];
            [[NSUserDefaults standardUserDefaults] setObject: @"changed" forKey: @"flushOverwritten"];
            exit(0); // no synchronize call
        }
        if (argc > 1 && !strcmp(argv[1], "read")) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            int bad = 0;
            bad += ![[defaults objectForKey: @"flushCF"] isEqual: @"cf-value"];
            bad += [defaults integerForKey: @"flushDefaults"] != 2;
            bad += ![[defaults objectForKey: @"flushOverwritten"] isEqual: @"changed"];
            return bad;
        }

        // start from a preferences file that holds an old value for one of the keys
        NSString *file = preferencesFile();
        [[NSFileManager defaultManager] removeItemAtPath: file error: nil];
        [@{ @"flushOverwritten": @"old" } writeToFile: file atomically: YES];

        CHECK(run(argv[0], "set-cf") == 0);
        CHECK(run(argv[0], "set-defaults") == 0);

        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile: file];
        CHECK([stored[@"flushCF"] isEqual: @"cf-value"]);
        CHECK([stored[@"flushDefaults"] isEqual: @2]);
        CHECK([stored[@"flushOverwritten"] isEqual: @"changed"]);
        CHECK(run(argv[0], "read") == 0);
        [[NSFileManager defaultManager] removeItemAtPath: file error: nil];
    }
    if (failures == 0)
        puts("PASS");
    return failures ? 1 : 0;
}
