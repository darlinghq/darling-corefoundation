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

#ifndef __CFSTRINGLOCALIZEDFORMAT__
#define __CFSTRINGLOCALIZEDFORMAT__

#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFDictionary.h>

// A string whose characters are format, carrying a .stringsdict entry
// (configuration) for the %#@variable@ specifiers in it; the format itself when
// Foundation, which provides the class of such strings, is not loaded.
CF_PRIVATE CFStringRef __CFStringCreateLocalizedFormat(CFStringRef format, CFDictionaryRef configuration);

// The .stringsdict entry carried by string, or NULL for any other string.
CF_PRIVATE CFDictionaryRef __CFStringGetLocalizedFormatConfiguration(CFStringRef string);

#endif
