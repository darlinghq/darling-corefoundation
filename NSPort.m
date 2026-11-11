#import <Foundation/NSPort.h>

@implementation NSPort
// the actual methods are in Foundation, in a category
@dynamic delegate;
@end

// macOS binds NSMachPort to CoreFoundation as well (NSMessagePort and
// NSSocketPort stay in Foundation). Its methods are a category in Foundation.
@implementation NSMachPort
@end
