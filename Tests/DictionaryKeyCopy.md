# NSDictionary key copying

Build DictionaryKeyCopy.m against Foundation/CoreFoundation (ARC or MRC) and run it under Darling. It stores an NSMutableString key through every public entry point (dictionaryWithObjects:forKeys:, dictionaryWithObject:forKey:, initWithObjects:forKeys:, literals, initWithDictionary:, setObject:forKey:, subscripting, setValue:forKey:, addEntriesFromDictionary:), mutates the original string and checks that lookup by the original value still works and the stored key is unchanged. It also checks that a key that does not conform to NSCopying raises NSInvalidArgumentException.

Installed baseline: one failure per entry point that stores keys (the stored key follows the mutation) and the non-NSCopying cases do not raise on the immutable path; candidate: zero failures.

Limitations: NSNull's copyWithZone: returns kCFNull without retaining it, so an NSNull key is not covered here; that is a separate, pre-existing issue. The initWithDictionary: and addEntriesFromDictionary: cases build their source with CFDictionaryCreateMutable and kCFTypeDictionaryKeyCallBacks, so the receiver is the only place a key can be copied.
