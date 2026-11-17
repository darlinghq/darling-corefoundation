/*
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * NSDateComponents valueForComponent: and setValue:forComponent: (macOS 10.9).
 *
 * Expected values were observed on macOS 10.14.4 and 26.7.3. Both read an unset unit as
 * NSDateComponentUndefined, map the calendar units era to nanosecond onto the matching
 * properties, and ignore setting (and read back as undefined) the calendar and time zone units,
 * a combination of units and unknown bits. Only macOS 26 also maps the deprecated week unit, so
 * that unit is not checked.
 */
#import <Foundation/Foundation.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

int main(void)
{
	@autoreleasepool {
		struct { NSCalendarUnit unit; const char *name; } units[] = {
			{ NSCalendarUnitEra, "era" }, { NSCalendarUnitYear, "year" }, { NSCalendarUnitMonth, "month" },
			{ NSCalendarUnitDay, "day" }, { NSCalendarUnitHour, "hour" }, { NSCalendarUnitMinute, "minute" },
			{ NSCalendarUnitSecond, "second" }, { NSCalendarUnitWeekday, "weekday" },
			{ NSCalendarUnitWeekdayOrdinal, "weekdayOrdinal" }, { NSCalendarUnitQuarter, "quarter" },
			{ NSCalendarUnitWeekOfMonth, "weekOfMonth" }, { NSCalendarUnitWeekOfYear, "weekOfYear" },
			{ NSCalendarUnitYearForWeekOfYear, "yearForWeekOfYear" }, { NSCalendarUnitNanosecond, "nanosecond" },
		};
		for (size_t i = 0; i < sizeof units / sizeof *units; i++) {
			NSDateComponents *c = [[NSDateComponents alloc] init];
			CHECK([c valueForComponent:units[i].unit] == NSDateComponentUndefined, "%s is undefined when unset", units[i].name);
			[c setValue:(NSInteger)(i + 3) forComponent:units[i].unit];
			CHECK([c valueForComponent:units[i].unit] == (NSInteger)(i + 3), "%s reads back what was set", units[i].name);
			/* the unit's own property agrees, and no other unit changed */
			NSString *key = [NSString stringWithUTF8String:units[i].name];
			CHECK([[c valueForKey:key] integerValue] == (NSInteger)(i + 3), "%s property agrees", units[i].name);
			int others = 0;
			for (size_t j = 0; j < sizeof units / sizeof *units; j++)
				if (j != i && [c valueForComponent:units[j].unit] != NSDateComponentUndefined)
					others++;
			CHECK(others == 0, "setting %s leaves the other units undefined", units[i].name);
		}

		NSDateComponents *c = [[NSDateComponents alloc] init];
		[c setYear:2024];
		CHECK([c valueForComponent:NSCalendarUnitYear] == 2024, "reads a value set through the property");
		[c setValue:NSDateComponentUndefined forComponent:NSCalendarUnitYear];
		CHECK(c.year == NSDateComponentUndefined, "setting undefined clears the unit");
		[c setValue:-7 forComponent:NSCalendarUnitDay];
		CHECK(c.day == -7 && [c valueForComponent:NSCalendarUnitDay] == -7, "negative values are kept");

		NSUInteger ignored[] = { NSCalendarUnitCalendar, NSCalendarUnitTimeZone, NSCalendarUnitYear | NSCalendarUnitMonth, 1UL << 30, 0 };
		for (size_t i = 0; i < sizeof ignored / sizeof *ignored; i++) {
			NSDateComponents *d = [[NSDateComponents alloc] init];
			CHECK([d valueForComponent:(NSCalendarUnit)ignored[i]] == NSDateComponentUndefined, "unit 0x%lx reads undefined", (unsigned long)ignored[i]);
			[d setValue:5 forComponent:(NSCalendarUnit)ignored[i]];
			CHECK([d valueForComponent:(NSCalendarUnit)ignored[i]] == NSDateComponentUndefined && d.year == NSDateComponentUndefined &&
			      d.month == NSDateComponentUndefined && d.calendar == nil && d.timeZone == nil, "setting unit 0x%lx changes nothing", (unsigned long)ignored[i]);
		}
	}
	printf("%s\n", failures ? "FAILED" : "PASS: NSDateComponents valueForComponent:");
	return failures != 0;
}
