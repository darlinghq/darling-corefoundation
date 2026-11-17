// Copyright (C) 2026 Lubos Dolezel
// nsurl-volume-keys <path>...: for each path, prints "== <path>" and then "<key> = <value>" for the NSURL volume
// resource keys, sorted by key name. A missing value prints as "nil", a boolean as 1 or 0, a URL as its absolute
// string and data as "<n> bytes". Exits 0 unless a path can't be turned into a URL. Also builds on macOS.
// The values macOS gives are in darling's tests/volumes.md.
#import <Foundation/Foundation.h>

static NSString *describe(id value)
{
    if (value == nil)
        return @"nil";
    if ([value isKindOfClass:[NSURL class]])
        return [value absoluteString];
    if ([value isKindOfClass:[NSData class]])
        return [NSString stringWithFormat:@"%lu bytes", (unsigned long)[value length]];
    if ([value isKindOfClass:[NSNumber class]])
        return [value boolValue] ? @"1" : @"0";
    return [value description];
}

int main(int argc, char **argv)
{
    @autoreleasepool
    {
        NSArray *keys = [@[
            NSURLIsVolumeKey,
            NSURLVolumeIdentifierKey,
            NSURLVolumeIsAutomountedKey,
            NSURLVolumeIsBrowsableKey,
            NSURLVolumeIsEjectableKey,
            NSURLVolumeIsInternalKey,
            NSURLVolumeIsLocalKey,
            NSURLVolumeIsReadOnlyKey,
            NSURLVolumeIsRemovableKey,
            NSURLVolumeIsRootFileSystemKey,
            NSURLVolumeLocalizedFormatDescriptionKey,
            NSURLVolumeLocalizedNameKey,
            NSURLVolumeMountFromLocationKey,
            NSURLVolumeNameKey,
            NSURLVolumeTypeNameKey,
            NSURLVolumeURLKey,
            NSURLVolumeUUIDStringKey,
        ] sortedArrayUsingSelector:@selector(compare:)];

        for (int i = 1; i < argc; i++)
        {
            NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[i]]];
            if (url == nil)
                return 1;
            printf("== %s\n", argv[i]);
            for (NSString *key in keys)
            {
                id value = nil;
                [url removeAllCachedResourceValues];
                [url getResourceValue:&value forKey:key error:NULL];
                printf("%s = %s\n", [key UTF8String], [describe(value) UTF8String]);
            }
        }
    }
    return 0;
}
