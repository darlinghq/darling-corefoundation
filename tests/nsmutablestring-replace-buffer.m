// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: -[NSMutableString replaceCharactersInRange:withCharacters:length:]
// and -replaceCharactersInRange:withCString:length: replace a range from a
// UniChar or C string buffer; both exist on NSMutableString instances on macOS.
#import <Foundation/Foundation.h>

@interface NSMutableString (BufferReplace)
- (void)replaceCharactersInRange:(NSRange)range withCharacters:(const unichar *)characters length:(NSUInteger)length;
- (void)replaceCharactersInRange:(NSRange)range withCString:(const char *)cString length:(NSUInteger)length;
@end

static int failures;

static void check(const char *label, BOOL ok)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        SEL characters = NSSelectorFromString(@"replaceCharactersInRange:withCharacters:length:");
        SEL cstring = NSSelectorFromString(@"replaceCharactersInRange:withCString:length:");
        NSMutableString *s = [NSMutableString stringWithString:@"hello world"];
        check("responds to the UniChar variant", [s respondsToSelector:characters]);
        check("responds to the C string variant", [s respondsToSelector:cstring]);

        const unichar u[] = {'W', 0x00F6, 'r', 'l', 'd'};
        [s replaceCharactersInRange:NSMakeRange(6, 5) withCharacters:u length:5];
        check("UniChar replacement", [s isEqualToString:@"hello Wörld"]);

        [s replaceCharactersInRange:NSMakeRange(0, 5) withCString:"howdy!!" length:5];
        check("C string replacement uses only length bytes", [s isEqualToString:@"howdy Wörld"]);

        [s replaceCharactersInRange:NSMakeRange(5, 0) withCString:"\xC3\xA9" length:2];
        check("C string bytes are read as UTF-8", [s isEqualToString:@"howdyé Wörld"]);

        [s replaceCharactersInRange:NSMakeRange(0, [s length]) withCharacters:u length:0];
        check("empty replacement deletes the range", [s length] == 0);
    }
    printf(failures ? "failures=%d\n" : "PASS\n", failures);
    return failures != 0;
}
