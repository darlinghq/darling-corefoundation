#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFURLEnumerator.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static void check_result(const char *label, BOOL ok) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void create_file(NSString *path) {
    int fd = open([path fileSystemRepresentation], O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd >= 0) {
        write(fd, "test", 4);
        close(fd);
    }
}

int main(void) {
    @autoreleasepool {
        char temp[] = "/tmp/darling-cfurl-enum-XXXXXX";
        char *root = mkdtemp(temp);
        if (!root) {
            fprintf(stderr, "Failed to create temp directory\n");
            return 2;
        }

        NSString *base = [NSString stringWithUTF8String:root];
        NSString *sub = [base stringByAppendingPathComponent:@"sub"];
        NSString *sub2 = [sub stringByAppendingPathComponent:@"sub2"];
        NSString *file1 = [base stringByAppendingPathComponent:@"file1.txt"];
        NSString *file2 = [sub stringByAppendingPathComponent:@"file2.txt"];
        NSString *file3 = [sub2 stringByAppendingPathComponent:@"file3.txt"];

        mkdir([sub fileSystemRepresentation], 0755);
        mkdir([sub2 fileSystemRepresentation], 0755);
        create_file(file1);
        create_file(file2);
        create_file(file3);

        CFURLRef baseURL = (CFURLRef)[NSURL fileURLWithPath:base];

        // 1. Default (flat) enumeration
        {
            CFURLEnumeratorRef enumer = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, baseURL, kCFURLEnumeratorDefaultBehavior, NULL);
            check_result("flat enumerator created", enumer != NULL);

            NSMutableArray *paths = [NSMutableArray array];
            CFURLRef url = NULL;
            CFErrorRef error = NULL;
            while (CFURLEnumeratorGetNextURL(enumer, &url, &error) == kCFURLEnumeratorSuccess) {
                if (url != NULL) {
                    [paths addObject:[(__bridge NSURL *)url lastPathComponent]];
                    CFRelease(url);
                }
            }
            check_result("flat enumeration does not descend", [paths count] == 2);
            check_result("flat enumeration contains file1.txt", [paths containsObject:@"file1.txt"]);
            check_result("flat enumeration contains sub", [paths containsObject:@"sub"]);
            check_result("flat enumeration does not contain file2.txt", ![paths containsObject:@"file2.txt"]);
            if (enumer) CFRelease(enumer);
        }

        // 2. Recursive enumeration
        {
            CFURLEnumeratorRef enumer = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, baseURL, kCFURLEnumeratorDescendRecursively, NULL);
            check_result("recursive enumerator created", enumer != NULL);

            NSMutableArray *paths = [NSMutableArray array];
            CFURLRef url = NULL;
            CFErrorRef error = NULL;
            while (CFURLEnumeratorGetNextURL(enumer, &url, &error) == kCFURLEnumeratorSuccess) {
                if (url != NULL) {
                    [paths addObject:[(__bridge NSURL *)url lastPathComponent]];
                    CFRelease(url);
                }
            }
            check_result("recursive enumeration descends into subdirectories", [paths count] == 5);
            check_result("recursive contains file1.txt", [paths containsObject:@"file1.txt"]);
            check_result("recursive contains sub", [paths containsObject:@"sub"]);
            check_result("recursive contains file2.txt", [paths containsObject:@"file2.txt"]);
            check_result("recursive contains sub2", [paths containsObject:@"sub2"]);
            check_result("recursive contains file3.txt", [paths containsObject:@"file3.txt"]);
            if (enumer) CFRelease(enumer);
        }

        // 3. url == NULL parameter handling (must not crash when descending or pushing)
        {
            CFURLEnumeratorRef enumer = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, baseURL, kCFURLEnumeratorDescendRecursively, NULL);
            check_result("url=NULL enumerator created", enumer != NULL);

            int count = 0;
            CFErrorRef error = NULL;
            while (CFURLEnumeratorGetNextURL(enumer, NULL, &error) == kCFURLEnumeratorSuccess) {
                count++;
            }
            check_result("url=NULL iteration visits all items without crashing", count == 5);
            if (enumer) CFRelease(enumer);
        }

        // 4. url == NULL with propertyKeys requested
        {
            CFArrayRef propKeys = (__bridge CFArrayRef)@[NSURLIsDirectoryKey, NSURLFileSizeKey];
            CFURLEnumeratorRef enumer = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, baseURL, kCFURLEnumeratorDescendRecursively, propKeys);
            check_result("url=NULL with properties enumerator created", enumer != NULL);

            int count = 0;
            CFErrorRef error = NULL;
            while (CFURLEnumeratorGetNextURL(enumer, NULL, &error) == kCFURLEnumeratorSuccess) {
                count++;
            }
            check_result("url=NULL with properties visits all items without crashing", count == 5);
            if (enumer) CFRelease(enumer);
        }

        // 5. CFURLEnumeratorSkipDescendents
        {
            CFURLEnumeratorRef enumer = CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault, baseURL, kCFURLEnumeratorDescendRecursively, NULL);
            NSMutableArray *paths = [NSMutableArray array];
            CFURLRef url = NULL;
            CFErrorRef error = NULL;
            while (CFURLEnumeratorGetNextURL(enumer, &url, &error) == kCFURLEnumeratorSuccess) {
                if (url != NULL) {
                    NSString *name = [(__bridge NSURL *)url lastPathComponent];
                    [paths addObject:name];
                    if ([name isEqualToString:@"sub"]) {
                        CFURLEnumeratorSkipDescendents(enumer);
                    }
                    CFRelease(url);
                }
            }
            check_result("skipDescendents skips nested directory contents", ![paths containsObject:@"file2.txt"] && ![paths containsObject:@"file3.txt"]);
            if (enumer) CFRelease(enumer);
        }

        // Cleanup temp files
        unlink([file3 fileSystemRepresentation]);
        rmdir([sub2 fileSystemRepresentation]);
        unlink([file2 fileSystemRepresentation]);
        rmdir([sub fileSystemRepresentation]);
        unlink([file1 fileSystemRepresentation]);
        rmdir(root);
    }

    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
