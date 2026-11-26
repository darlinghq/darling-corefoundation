/*
This file is part of Darling.

Copyright (C) 2026 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// _CFAppVersionCheckLessThan, the SPI with which a framework asks whether the
// running application is a given one, older than a given version. Its
// behaviour is that observed on macOS 26.7.3 and Mac OS X 10.14.4 (test:
// tests/CFAppVersionCheckLessThan.c):
//  - the main bundle's identifier has to equal the one asked about, case and
//    all;
//  - the version is the leading decimal number of CFBundleShortVersionString
//    ("2.5.3" is 2.5), and an application without one, or whose string does
//    not start with a number, has version 0; CFBundleVersion is not read.
#include <CoreFoundation/CFBundle.h>
#include <CoreFoundation/CFString.h>
#include <stdlib.h>
#include <xlocale.h>

CF_EXPORT Boolean _CFAppVersionCheckLessThan(CFStringRef bundleID, int linkedOnAnOlderSystemThan, double versionNumberLessThan);

static double mainBundleShortVersion(CFBundleRef bundle)
{
    CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("CFBundleShortVersionString"));
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID())
        return 0;

    char text[64];
    if (!CFStringGetCString((CFStringRef) value, text, sizeof text, kCFStringEncodingUTF8))
        return 0;
    // The C locale: a version is written with a full stop wherever it runs.
    return strtod_l(text, NULL, LC_C_LOCALE);
}

Boolean _CFAppVersionCheckLessThan(CFStringRef bundleID, int linkedOnAnOlderSystemThan, double versionNumberLessThan)
{
    // QUIRK: only -1 (no SDK condition, the value callers pass) has been seen
    // to give true; 0, 1 and 100000 give false whatever the application and
    // version are, and what the argument compares against was not determined.
    // Evidence: black-box observation on macOS 26.7.3 and Mac OS X 10.14.4
    // (tier 2). Test: "quirk: a linked-on condition is never met" in
    // tests/CFAppVersionCheckLessThan.c.
    if (linkedOnAnOlderSystemThan != -1)
        return false;

    // macOS 26.7.3 traps on a NULL identifier; no application has none.
    if (bundleID == NULL)
        return false;
    CFBundleRef bundle = CFBundleGetMainBundle();
    if (bundle == NULL)
        return false;
    CFStringRef identifier = CFBundleGetIdentifier(bundle);
    if (identifier == NULL || CFStringCompare(identifier, bundleID, 0) != kCFCompareEqualTo)
        return false;

    return mainBundleShortVersion(bundle) < versionNumberLessThan;
}
