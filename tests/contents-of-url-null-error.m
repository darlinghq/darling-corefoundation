// Copyright (C) 2026 Lubos Dolezel
// The ...WithContentsOfURL:error: loaders may be called with a NULL error
// pointer; they must not write through it, and must still fill it when given.
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

int main(void)
{
	@autoreleasepool {
		NSURL *missing = [NSURL fileURLWithPath:@"/nonexistent-dir-for-test/file.plist"];

		CHECK([NSArray arrayWithContentsOfURL:missing error:NULL] == nil);
		CHECK([NSDictionary dictionaryWithContentsOfURL:missing error:NULL] == nil);
		CHECK([[NSDictionary alloc] initWithContentsOfURL:missing error:NULL] == nil);

		NSError *err = nil;
		CHECK([NSArray arrayWithContentsOfURL:missing error:&err] == nil);
		CHECK(err != nil);
		err = nil;
		CHECK([NSDictionary dictionaryWithContentsOfURL:missing error:&err] == nil);
		CHECK(err != nil);
		err = nil;
		CHECK([[NSDictionary alloc] initWithContentsOfURL:missing error:&err] == nil);
		CHECK(err != nil);

		// success path with NULL
		NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"v471-test.plist"];
		NSDictionary *d = @{ @"a": @1 };
		CHECK([d writeToFile:path atomically:YES]);
		NSURL *u = [NSURL fileURLWithPath:path];
		CHECK([[NSDictionary dictionaryWithContentsOfURL:u error:NULL] isEqual:d]);
		CHECK([[[NSDictionary alloc] initWithContentsOfURL:u error:NULL] isEqual:d]);
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	if (failures) return 1;
	printf("PASS\n");
	return 0;
}
