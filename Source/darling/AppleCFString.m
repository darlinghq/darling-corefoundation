#import "AppleCFString.h"
#import <Foundation/NSException.h>
#include <string.h>

#if 0
extern Class* _OBJC_CLASS_AppleCFString;
extern Class* __CFConstantStringClassReference;

extern Class* __CFConstantStringClassReference  __attribute__ ((weak, alias ("_OBJC_CLASS_AppleCFString")));
#endif

#if 1
void __forceAppleCFStringLoad()
{
	// The runtime seems to expect at least one instance of AppleCFString to be created
	// before it starts working. Since constant string in application images are not
	// "created", random failures occured.
	[[AppleCFString alloc] dealloc];
}
#endif

extern int NXArgc;
extern char** NXArgv;
extern char*** __darwin_environ;

@implementation AppleCFString
+ (void) load
{
	GSInitializeProcess(NXArgc, NXArgv, __darwin_environ);
	 __forceAppleCFStringLoad();
}

- (NSUInteger)length
{
	return _length;
}

- (unichar)characterAtIndex:(NSUInteger)index
{
	if (index >= _length)
		[NSException raise: NSRangeException format: @"Invalid index"];

	if (_flags & apple_unicode)
		return _data._unicodeData[index];
	else
		return _data._asciiData[index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)aRange
{
	if (aRange.location+aRange.length > _length)
		[NSException raise: NSRangeException format: @"Invalid range"];
	
	if (_flags & apple_unicode)
	{
		memcpy(buffer, _data._unicodeData + aRange.location, aRange.length);
	}
	else
	{
		for (int i = 0; i < aRange.length; i++)
			buffer[i] = _data._asciiData[i+aRange.location];
	}
}

- (const char *)UTF8String
{
	if (_flags & apple_unicode)
		return [super UTF8String];
	else
		return _data._asciiData;
}

- (NSUInteger) retainCount
{
	return UINT_MAX;
}

- (id) retain
{
	return self;
}

- (void) release
{
}

- (id) autorelease
{
	return self;
}

- (NSZone*) zone
{
	return NSDefaultMallocZone();
}

- (CFTypeID) _cfTypeID
{
	return CFStringGetTypeID();
}

@end

