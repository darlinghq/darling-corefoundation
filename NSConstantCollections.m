//
//  NSConstantCollections.m
//  CoreFoundation
//
//  Classes for collection literals (`@[...]`, `@{...}`) that newer clang emits as constant objects
//  directly into binaries, plus the empty collection singletons such binaries reference.
//  The object layouts must match clang's exactly (see NSConstantArray/NSConstantDictionary in
//  clang/lib/CodeGen/CGObjCMac.cpp), so the classes read the structs directly instead of
//  declaring ivars.
//

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import "NSObjectInternal.h"

struct __NSConstantArrayLayout {
    Class isa;
    NSUInteger count;
    const id *objects;
};

struct __NSConstantDictionaryLayout {
    Class isa;
    NSUInteger hashOptions;
    NSUInteger count;
    const id *keys;
    const id *objects;
};

#define ARRAY_LAYOUT(obj) ((struct __NSConstantArrayLayout *)(obj))
#define DICTIONARY_LAYOUT(obj) ((struct __NSConstantDictionaryLayout *)(obj))

__attribute__((visibility("default")))
@interface NSConstantArray : NSArray
@end

@implementation NSConstantArray

SINGLETON_RR()

- (NSUInteger)count
{
    return ARRAY_LAYOUT(self)->count;
}

- (id)objectAtIndex:(NSUInteger)index
{
    if (index >= ARRAY_LAYOUT(self)->count)
    {
        [NSException raise:NSRangeException format:@"index %lu beyond bounds [0 .. %lu]", (unsigned long)index, (unsigned long)ARRAY_LAYOUT(self)->count];
        return nil;
    }
    return ARRAY_LAYOUT(self)->objects[index];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{
    if (state->state != 0)
    {
        return 0;
    }
    state->state = 1;
    state->itemsPtr = (id __unsafe_unretained *)ARRAY_LAYOUT(self)->objects;
    state->mutationsPtr = (unsigned long *)&ARRAY_LAYOUT(self)->count;
    return ARRAY_LAYOUT(self)->count;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

__attribute__((visibility("default")))
@interface NSConstantDictionary : NSDictionary
@end

@implementation NSConstantDictionary

SINGLETON_RR()

- (NSUInteger)count
{
    return DICTIONARY_LAYOUT(self)->count;
}

- (id)objectForKey:(id)key
{
    if (key == nil)
    {
        return nil;
    }
    struct __NSConstantDictionaryLayout *layout = DICTIONARY_LAYOUT(self);
    for (NSUInteger i = 0; i < layout->count; i++)
    {
        if (layout->keys[i] == key || [layout->keys[i] isEqual:key])
        {
            return layout->objects[i];
        }
    }
    return nil;
}

- (NSEnumerator *)keyEnumerator
{
    struct __NSConstantDictionaryLayout *layout = DICTIONARY_LAYOUT(self);
    if (layout->count == 0)
    {
        return [[NSArray array] objectEnumerator];
    }
    return [[NSArray arrayWithObjects:layout->keys count:layout->count] objectEnumerator];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{
    if (state->state != 0)
    {
        return 0;
    }
    state->state = 1;
    state->itemsPtr = (id __unsafe_unretained *)DICTIONARY_LAYOUT(self)->keys;
    state->mutationsPtr = (unsigned long *)&DICTIONARY_LAYOUT(self)->count;
    return DICTIONARY_LAYOUT(self)->count;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

// Empty `@[]` and `@{}` literals reference these singletons instead of emitting their own objects.
#if __OBJC2__
extern struct { Class isa; } _NSConstantArrayClass __asm("_OBJC_CLASS_$_NSConstantArray");
extern struct { Class isa; } _NSConstantDictionaryClass __asm("_OBJC_CLASS_$_NSConstantDictionary");
#else
extern struct { Class isa; } _NSConstantArrayClass __asm(".objc_class_name_NSConstantArray");
extern struct { Class isa; } _NSConstantDictionaryClass __asm(".objc_class_name_NSConstantDictionary");
#endif

__attribute__((visibility("default")))
struct __NSConstantArrayLayout __NSArray0__struct = {
    (Class)&_NSConstantArrayClass, 0, NULL
};

__attribute__((visibility("default")))
struct __NSConstantDictionaryLayout __NSDictionary0__struct = {
    (Class)&_NSConstantDictionaryClass, 0, 0, NULL, NULL
};
