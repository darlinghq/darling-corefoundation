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

// Strings from .stringsdict tables. Foundation provides the string class (a
// mutable string subclass, see its NSLocalizedFormatString.m): its characters are
// the entry's NSStringLocalizedFormatKey value, and it keeps the whole entry,
// which string formatting consults to expand %#@variable@ specifiers. The class
// is found at run time, like the other Foundation classes CoreFoundation uses;
// without Foundation the format alone is returned.

#import <objc/runtime.h>
#import <objc/message.h>
#include "CFInternal.h"
#include "CFStringLocalizedFormat.h"

#define LOCALIZED_FORMAT_STRING_CLASS "__NSLocalizedFormatString"

static Class __CFLocalizedFormatStringClass(void) {
    static Class cls;
    if (!cls) cls = objc_lookUpClass(LOCALIZED_FORMAT_STRING_CLASS);
    return cls;
}

CF_PRIVATE CFStringRef __CFStringCreateLocalizedFormat(CFStringRef format, CFDictionaryRef configuration) {
    Class cls = __CFLocalizedFormatStringClass();
    if (!cls) return (CFStringRef)CFRetain(format);
    id string = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    return (CFStringRef)((id (*)(id, SEL, id, id))objc_msgSend)(string, sel_registerName("_initWithFormat:configuration:"), (id)format, (id)configuration);
}

CF_PRIVATE CFDictionaryRef __CFStringGetLocalizedFormatConfiguration(CFStringRef string) {
    if (!string || !CF_IS_OBJC(CFStringGetTypeID(), string)) return NULL;
    Class cls = __CFLocalizedFormatStringClass();
    if (!cls) return NULL;
    for (Class c = object_getClass((id)string); c; c = class_getSuperclass(c)) {
        if (c == cls) return (CFDictionaryRef)((id (*)(id, SEL))objc_msgSend)((id)string, sel_registerName("_localizedFormatConfiguration"));
    }
    return NULL;
}
