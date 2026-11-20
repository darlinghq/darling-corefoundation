// Copyright (C) 2026 Lubos Dolezel
//
// Localized strings from a .stringsdict table and the %#@variable@ plural rule
// format they carry. See StringsDictPluralFormat.md.

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

static int failures;

static void expect(const char *label, NSString *actual, NSString *expected) {
    BOOL ok = [actual isKindOfClass:[NSString class]] && [actual isEqualToString:expected];
    printf("%s %s: got \"%s\", expected \"%s\"\n", ok ? "PASS" : "FAIL", label,
           actual ? [actual UTF8String] : "(nil)", [expected UTF8String]);
    failures += !ok;
}

static void writePlist(id plist, NSString *path) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    if (![data writeToFile:path atomically:NO]) {
        printf("cannot write %s\n", [path UTF8String]);
        exit(2);
    }
}

static NSDictionary *plural(NSDictionary *formats) {
    NSMutableDictionary *variable = [NSMutableDictionary dictionaryWithDictionary:formats];
    variable[@"NSStringFormatSpecTypeKey"] = @"NSStringPluralRuleType";
    variable[@"NSStringFormatValueTypeKey"] = @"lu";
    return variable;
}

static NSString *withLocale(NSString *format, NSString *localeIdentifier, ...) {
    va_list args;
    va_start(args, localeIdentifier);
    NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier] autorelease];
    NSString *result = [[[NSString alloc] initWithFormat:format locale:locale arguments:args] autorelease];
    va_end(args);
    return result;
}

int main(void) {
    @autoreleasepool {
        char temp[] = "/tmp/darling-stringsdict-XXXXXX";
        if (!mkdtemp(temp)) return 2;
        NSString *root = [NSString stringWithUTF8String:temp];
        for (NSString *dir in @[@"Plural.bundle", @"Plural.bundle/Contents", @"Plural.bundle/Contents/Resources",
                                @"Plural.bundle/Contents/Resources/Base.lproj",
                                @"French.bundle", @"French.bundle/Contents", @"French.bundle/Contents/Resources",
                                @"French.bundle/Contents/Resources/fr.lproj"])
            if (mkdir([[root stringByAppendingPathComponent:dir] fileSystemRepresentation], 0700) != 0) return 2;

        NSString *pluralPath = [root stringByAppendingPathComponent:@"Plural.bundle"];
        NSString *frenchPath = [root stringByAppendingPathComponent:@"French.bundle"];
        writePlist(@{@"CFBundleIdentifier": @"org.darlinghq.stringsdict-test", @"CFBundleDevelopmentRegion": @"en"},
                   [pluralPath stringByAppendingPathComponent:@"Contents/Info.plist"]);
        writePlist(@{@"CFBundleIdentifier": @"org.darlinghq.stringsdict-test-fr", @"CFBundleDevelopmentRegion": @"fr"},
                   [frenchPath stringByAppendingPathComponent:@"Contents/Info.plist"]);
        writePlist(@{
            @"ITEMS": @{@"NSStringLocalizedFormatKey": @"%#@n@",
                        @"n": plural(@{@"zero": @"no items", @"one": @"%lu item", @"other": @"%lu items"})},
            @"NOZERO": @{@"NSStringLocalizedFormatKey": @"%#@n@",
                         @"n": plural(@{@"one": @"%lu thing", @"other": @"%lu things"})},
            @"TWO": @{@"NSStringLocalizedFormatKey": @"%#@a@ in %#@b@",
                      @"a": plural(@{@"one": @"%lu file", @"other": @"%lu files"}),
                      @"b": plural(@{@"one": @"%lu folder", @"other": @"%lu folders"})},
            @"MIXED": @{@"NSStringLocalizedFormatKey": @"%@ has %#@n@",
                        @"n": plural(@{@"one": @"%lu cat", @"other": @"%lu cats"})},
            @"INNERTEXT": @{@"NSStringLocalizedFormatKey": @"Got %#@n@!",
                            @"n": plural(@{@"one": @"one apple", @"other": @"%lu apples"})},
            @"BOTH": @{@"NSStringLocalizedFormatKey": @"%#@n@ (dict)",
                       @"n": plural(@{@"one": @"%lu x", @"other": @"%lu xs"})},
            @"PLAIN": @"plain string in stringsdict",
        }, [pluralPath stringByAppendingPathComponent:@"Contents/Resources/Base.lproj/Localizable.stringsdict"]);
        [@"\"BOTH\" = \"from strings %lu\";\n\"ONLYSTRINGS\" = \"strings only\";\n"
            writeToFile:[pluralPath stringByAppendingPathComponent:@"Contents/Resources/Base.lproj/Localizable.strings"]
             atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        writePlist(@{@"FR": @{@"NSStringLocalizedFormatKey": @"%#@n@",
                              @"n": plural(@{@"one": @"%lu un", @"other": @"%lu autre"})}},
                   [frenchPath stringByAppendingPathComponent:@"Contents/Resources/fr.lproj/Localizable.stringsdict"]);

        NSBundle *bundle = [NSBundle bundleWithPath:pluralPath];
        NSString *items = [bundle localizedStringForKey:@"ITEMS" value:nil table:nil];
        expect("value is the NSStringLocalizedFormatKey", items, @"%#@n@");
        expect("English 1", withLocale(items, @"en_US", 1UL), @"1 item");
        expect("English 2", withLocale(items, @"en_US", 2UL), @"2 items");
        expect("quirk: zero category in English", withLocale(items, @"en_US", 0UL), @"no items");
        expect("localizedStringWithFormat 1", [NSString localizedStringWithFormat:items, 1UL], @"1 item");
        expect("stringWithFormat 1", [NSString stringWithFormat:items, 1UL], @"1 item");
        expect("stringWithFormat 5", [NSString stringWithFormat:items, 5UL], @"5 items");

        NSString *noZero = [bundle localizedStringForKey:@"NOZERO" value:nil table:nil];
        expect("no zero format: English 0 is other", withLocale(noZero, @"en_US", 0UL), @"0 things");
        expect("French rules: 0 is one", withLocale(noZero, @"fr_FR", 0UL), @"0 thing");
        expect("French rules: 2 is other", withLocale(noZero, @"fr_FR", 2UL), @"2 things");
        expect("quirk: no locale: English rules", [NSString stringWithFormat:noZero, 0UL], @"0 things");

        expect("two variables", withLocale([bundle localizedStringForKey:@"TWO" value:nil table:nil], @"en_US", 3UL, 1UL), @"3 files in 1 folder");
        expect("two variables, other order", withLocale([bundle localizedStringForKey:@"TWO" value:nil table:nil], @"en_US", 1UL, 2UL), @"1 file in 2 folders");
        expect("object before a variable", withLocale([bundle localizedStringForKey:@"MIXED" value:nil table:nil], @"en_US", @"Bob", 4UL), @"Bob has 4 cats");
        expect("text around a variable, no number", withLocale([bundle localizedStringForKey:@"INNERTEXT" value:nil table:nil], @"en_US", 1UL), @"Got one apple!");
        expect("text around a variable", withLocale([bundle localizedStringForKey:@"INNERTEXT" value:nil table:nil], @"en_US", 3UL), @"Got 3 apples!");

        NSString *both = [bundle localizedStringForKey:@"BOTH" value:nil table:nil];
        expect("stringsdict entry wins over .strings", both, @"%#@n@ (dict)");
        expect("stringsdict entry wins over .strings, formatted", withLocale(both, @"en_US", 2UL), @"2 xs (dict)");
        expect("plain string entry", [bundle localizedStringForKey:@"PLAIN" value:nil table:nil], @"plain string in stringsdict");
        expect(".strings entry beside a stringsdict", [bundle localizedStringForKey:@"ONLYSTRINGS" value:nil table:nil], @"strings only");

        expect("copy keeps the variables", [NSString stringWithFormat:[[items copy] autorelease], 1UL], @"1 item");
        expect("mutableCopy keeps the variables", [NSString stringWithFormat:[[items mutableCopy] autorelease], 1UL], @"1 item");
        NSMutableString *appended = [NSMutableString string];
        [appended appendFormat:items, 3UL];
        expect("appendFormat", appended, @"3 items");

        CFBundleRef cfBundle = CFBundleCreate(NULL, (CFURLRef)[NSURL fileURLWithPath:pluralPath]);
        CFStringRef cfItems = CFBundleCopyLocalizedString(cfBundle, CFSTR("ITEMS"), NULL, NULL);
        expect("CFBundleCopyLocalizedString", (NSString *)cfItems, @"%#@n@");
        expect("CFStringCreateWithFormat", [(NSString *)CFStringCreateWithFormat(NULL, NULL, cfItems, 1UL) autorelease], @"1 item");
        CFRelease(cfItems);
        CFRelease(cfBundle);

        NSString *fr = [[NSBundle bundleWithPath:frenchPath] localizedStringForKey:@"FR" value:nil table:nil];
        expect("French bundle, French locale 0", withLocale(fr, @"fr_FR", 0UL), @"0 un");
        expect("French bundle, English locale 0", withLocale(fr, @"en_US", 0UL), @"0 autre");
        expect("quirk: French bundle, no locale 0", [NSString stringWithFormat:fr, 0UL], @"0 autre");

        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
