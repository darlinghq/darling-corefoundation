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

#ifndef __CFDISTRIBUTEDNOTIFICATIONINTERNAL_H__
#define __CFDISTRIBUTEDNOTIFICATIONINTERNAL_H__

#include <CoreFoundation/CFNotificationCenter.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFDistributedNotification_Private.h>

CF_EXTERN_C_BEGIN

void _CFDistributedAddObserver(const void *observer, CFNotificationCallback callBack, CFStringRef name,
                               CFStringRef object, CFNotificationSuspensionBehavior behavior);
void _CFDistributedRemoveObserver(const void *observer, CFStringRef name, CFStringRef object);
void _CFDistributedSetSuspended(Boolean suspended);
Boolean _CFDistributedIsSuspended(void);
void _CFDistributedPost(CFStringRef name, CFStringRef object, CFDictionaryRef userInfo, Boolean immediate);

CF_EXTERN_C_END

#endif
