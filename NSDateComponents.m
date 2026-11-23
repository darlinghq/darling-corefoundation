//
//  NSDateComponents.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import "NSCalendarInternal.h"
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <objc/message.h>
#import "ForFoundationOnly.h"

typedef struct {
    NSUInteger unitFlags;
    NSInteger era;
    NSInteger year;
    NSInteger month;
    NSInteger dayOfMonth;
    NSInteger hourOfDay;
    NSInteger minute;
    NSInteger second;
    NSInteger nanosecond;
    NSInteger weekOfYear;
    NSInteger weekOfMonth;
    NSInteger yearWeekOfYear;
    NSInteger weekday;
    NSInteger quarter;
    NSInteger weekdayOrdinal;
    NSCalendar *calendar;
    NSTimeZone *timeZone;
    BOOL leapMonth;
} NSDateComponentParts;

@implementation NSDateComponents

+ (id)allocWithZone:(NSZone *)zone
{
    return (id)___CFAllocateObject2(self, sizeof(NSDateComponentParts));
}

- (id)copyWithZone:(NSZone *)zone
{
    NSDateComponents *copy = [[[self class] allocWithZone:zone] init];
    copy.day = self.day;
    copy.month = self.month;
    copy.year = self.year;
    copy.hour = self.hour;
    copy.minute = self.minute;
    copy.second = self.second;
    copy.nanosecond = self.nanosecond;
    copy.weekday = self.weekday;
    copy.week = self.week;
    copy.era = self.era;
    copy.quarter = self.quarter;
    copy.weekOfYear = self.weekOfYear;
    copy.yearForWeekOfYear = self.yearForWeekOfYear;
    copy.weekdayOrdinal = self.weekdayOrdinal;
    copy.calendar = self.calendar;
    copy.timeZone = self.timeZone;
    [copy setLeapMonth:[self isLeapMonth]];
    return copy;
}

- (id)init
{
    self = [super init];

    if (self)
    {
        NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
        parts->era = NSDateComponentUndefined;
        parts->year = NSDateComponentUndefined;
        parts->month = NSDateComponentUndefined;
        parts->dayOfMonth = NSDateComponentUndefined;
        parts->hourOfDay = NSDateComponentUndefined;
        parts->minute = NSDateComponentUndefined;
        parts->second = NSDateComponentUndefined;
        parts->nanosecond = NSDateComponentUndefined;
        parts->weekOfYear = NSDateComponentUndefined;
        parts->weekOfMonth = NSDateComponentUndefined;
        parts->yearWeekOfYear = NSDateComponentUndefined;
        parts->weekday = NSDateComponentUndefined;
        parts->quarter = NSDateComponentUndefined;
        parts->weekdayOrdinal = NSDateComponentUndefined;
    }

    return self;
}

- (NSInteger)day
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->dayOfMonth;
}

- (void)setDay:(NSInteger)day
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitDay;
    parts->dayOfMonth = day;
}

- (NSInteger)month
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->month;
}

- (void)setMonth:(NSInteger)month
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitMonth;
    parts->month = month;
}

- (NSInteger)year
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->year;
}

- (void)setYear:(NSInteger)year
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitYear;
    parts->year = year;
}

- (NSInteger)hour
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->hourOfDay;
}

- (void)setHour:(NSInteger)hour
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitHour;
    parts->hourOfDay = hour;
}

- (NSInteger)minute
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->minute;
}

- (void)setMinute:(NSInteger)minute
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitMinute;
    parts->minute = minute;
}

- (NSInteger)second
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->second;
}

- (void)setSecond:(NSInteger)second
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitSecond;
    parts->second = second;
}

- (NSInteger)nanosecond
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->nanosecond;
}

- (void)setNanosecond:(NSInteger)nanosecond
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitNanosecond;
    parts->nanosecond = nanosecond;
}

- (NSInteger)weekday
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->weekday;
}

- (void)setWeekday:(NSInteger)weekday
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitWeekday;
    parts->weekday = weekday;
}

- (NSInteger)week
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->weekOfMonth;
}

- (void)setWeek:(NSInteger)week
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitWeekOfMonth;
    parts->weekOfMonth = week;
}

- (NSInteger)era
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->era;
}

- (void)setEra:(NSInteger)era
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitEra;
    parts->era = era;
}

- (NSInteger)quarter
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->quarter;
}

- (void)setQuarter:(NSInteger)quarter
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitQuarter;
    parts->quarter = quarter;
}

- (NSInteger)weekOfMonth
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->weekOfMonth;
}

- (void)setWeekOfMonth:(NSInteger)weekOfMonth
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitWeekOfMonth;
    parts->weekOfMonth = weekOfMonth;
}

- (NSInteger)weekOfYear
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->weekOfYear;
}

- (void)setWeekOfYear:(NSInteger)weekOfYear
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitWeekOfYear;
    parts->weekOfYear = weekOfYear;
}

- (NSInteger)yearForWeekOfYear
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->yearWeekOfYear;
}

- (void)setYearForWeekOfYear:(NSInteger)yearWeekOfYear
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitYearForWeekOfYear;
    parts->yearWeekOfYear = yearWeekOfYear;
}

- (NSInteger)weekdayOrdinal
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->weekdayOrdinal;
}

- (void)setWeekdayOrdinal:(NSInteger)weekdayOrdinal
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->unitFlags |= NSCalendarUnitWeekdayOrdinal;
    parts->weekdayOrdinal = weekdayOrdinal;
}

// The components by unit (NSDateComponents API since macOS 10.9). Units that are not a
// component (calendar, time zone, week as of the macOS 10.14 behaviour) read as undefined and are
// ignored when set, as on macOS.
- (NSInteger)valueForComponent:(NSCalendarUnit)unit
{
    switch (unit)
    {
        case NSCalendarUnitEra: return [self era];
        case NSCalendarUnitYear: return [self year];
        case NSCalendarUnitMonth: return [self month];
        case NSCalendarUnitDay: return [self day];
        case NSCalendarUnitHour: return [self hour];
        case NSCalendarUnitMinute: return [self minute];
        case NSCalendarUnitSecond: return [self second];
        case NSCalendarUnitWeekday: return [self weekday];
        case NSCalendarUnitWeekdayOrdinal: return [self weekdayOrdinal];
        case NSCalendarUnitQuarter: return [self quarter];
        case NSCalendarUnitWeekOfMonth: return [self weekOfMonth];
        case NSCalendarUnitWeekOfYear: return [self weekOfYear];
        case NSCalendarUnitYearForWeekOfYear: return [self yearForWeekOfYear];
        case NSCalendarUnitNanosecond: return [self nanosecond];
        default: return NSDateComponentUndefined;
    }
}

- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit
{
    switch (unit)
    {
        case NSCalendarUnitEra: [self setEra:value]; break;
        case NSCalendarUnitYear: [self setYear:value]; break;
        case NSCalendarUnitMonth: [self setMonth:value]; break;
        case NSCalendarUnitDay: [self setDay:value]; break;
        case NSCalendarUnitHour: [self setHour:value]; break;
        case NSCalendarUnitMinute: [self setMinute:value]; break;
        case NSCalendarUnitSecond: [self setSecond:value]; break;
        case NSCalendarUnitWeekday: [self setWeekday:value]; break;
        case NSCalendarUnitWeekdayOrdinal: [self setWeekdayOrdinal:value]; break;
        case NSCalendarUnitQuarter: [self setQuarter:value]; break;
        case NSCalendarUnitWeekOfMonth: [self setWeekOfMonth:value]; break;
        case NSCalendarUnitWeekOfYear: [self setWeekOfYear:value]; break;
        case NSCalendarUnitYearForWeekOfYear: [self setYearForWeekOfYear:value]; break;
        case NSCalendarUnitNanosecond: [self setNanosecond:value]; break;
        default: break;
    }
}

- (NSCalendar *)calendar
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->calendar;
}

- (void)setCalendar:(NSCalendar *)calendar
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);

    if (parts->calendar != calendar)
    {
        [parts->calendar release];
        parts->calendar = [calendar retain];
    }
}

- (NSTimeZone *)timeZone
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->timeZone;
}

- (void)setTimeZone:(NSTimeZone *)timeZone
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    
    if (parts->timeZone != timeZone)
    {
        [parts->timeZone release];
        parts->timeZone = [timeZone retain];
    }
}

- (BOOL)isLeapMonth
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    return parts->leapMonth;
}

- (void)setLeapMonth:(BOOL)leapMonth
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    parts->leapMonth = leapMonth;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

// Only the components that are set are archived, as NSDateComponentUndefined
// marks the others; the repeated-day flag is always archived as NO because
// this class does not track it.
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding])
    {
        [NSException raise:NSInvalidArgumentException format:@"NSDateComponents requires a keyed coder"];
        return;
    }
    struct { NSString *key; SEL getter; } fields[] = {
        { @"NS.era", @selector(era) }, { @"NS.year", @selector(year) }, { @"NS.month", @selector(month) },
        { @"NS.day", @selector(day) }, { @"NS.hour", @selector(hour) }, { @"NS.minute", @selector(minute) },
        { @"NS.second", @selector(second) }, { @"NS.nanosec", @selector(nanosecond) },
        { @"NS.weekOfYear", @selector(weekOfYear) }, { @"NS.weekOfMonth", @selector(weekOfMonth) },
        { @"NS.yearForWOY", @selector(yearForWeekOfYear) }, { @"NS.weekday", @selector(weekday) },
        { @"NS.quarter", @selector(quarter) }, { @"NS.weekdayOrdinal", @selector(weekdayOrdinal) },
    };
    for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++)
    {
        NSInteger value = ((NSInteger (*)(id, SEL))objc_msgSend)(self, fields[i].getter);
        if (value != NSDateComponentUndefined)
        {
            [coder encodeInteger:value forKey:fields[i].key];
        }
    }
    [coder encodeBool:[self isLeapMonth] forKey:@"NS.leapMonth"];
    [coder encodeBool:NO forKey:@"NS.repeatedDay"];
    [coder encodeObject:[self calendar] forKey:@"NS.calendar"];
    [coder encodeObject:[self timeZone] forKey:@"NS.timezone"];
}

- (id)initWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding])
    {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"NSDateComponents requires a keyed coder"];
        return nil;
    }
    self = [self init];
    if (self == nil)
    {
        return nil;
    }
    struct { NSString *key; SEL setter; } fields[] = {
        { @"NS.era", @selector(setEra:) }, { @"NS.year", @selector(setYear:) }, { @"NS.month", @selector(setMonth:) },
        { @"NS.day", @selector(setDay:) }, { @"NS.hour", @selector(setHour:) }, { @"NS.minute", @selector(setMinute:) },
        { @"NS.second", @selector(setSecond:) }, { @"NS.nanosec", @selector(setNanosecond:) },
        { @"NS.weekOfYear", @selector(setWeekOfYear:) }, { @"NS.weekOfMonth", @selector(setWeekOfMonth:) },
        { @"NS.yearForWOY", @selector(setYearForWeekOfYear:) }, { @"NS.weekday", @selector(setWeekday:) },
        { @"NS.quarter", @selector(setQuarter:) }, { @"NS.weekdayOrdinal", @selector(setWeekdayOrdinal:) },
    };
    for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++)
    {
        if ([coder containsValueForKey:fields[i].key])
        {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, fields[i].setter, [coder decodeIntegerForKey:fields[i].key]);
        }
    }
    [self setLeapMonth:[coder decodeBoolForKey:@"NS.leapMonth"]];
    NSCalendar *calendar = [coder decodeObjectOfClass:[NSCalendar class] forKey:@"NS.calendar"];
    NSTimeZone *timeZone = [coder decodeObjectOfClass:[NSTimeZone class] forKey:@"NS.timezone"];
    // An archive can store a property-list value (string, number, data) under these keys, and such
    // values are not checked against the classes passed to -decodeObjectOfClass:forKey:.
    if ((calendar != nil && ![calendar isKindOfClass:[NSCalendar class]]) ||
        (timeZone != nil && ![timeZone isKindOfClass:[NSTimeZone class]]))
    {
        [self release];
        return nil;
    }
    [self setCalendar:calendar];
    [self setTimeZone:timeZone];
    return self;
}

-(NSDate *)date
{
    NSDateComponentParts *parts = (NSDateComponentParts *)object_getIndexedIvars(self);
    if (parts->calendar != nil)
    {
        return [parts->calendar dateFromComponents:self];
    }
    return nil;
}

@end
