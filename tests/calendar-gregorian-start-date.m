// Run linked against the candidate Foundation/CoreFoundation runtime.
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdio.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
    NSDate *changeover = [NSDate dateWithTimeIntervalSinceReferenceDate:-1000000000.0];
    [calendar setGregorianStartDate:changeover];
    assert([[calendar gregorianStartDate] isEqual:changeover]);
    [pool drain];
    puts("PASS: gregorianStartDate round-trips the date passed to the setter");
    return 0;
}
