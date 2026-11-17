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

/*
 * The messages between CoreFoundation's distributed notification center and the distributed notification daemon
 * (distnoted). Private: the Mach service name is the one the user's distnoted job claims on macOS; the messages are
 * Darling's own. Every message is an XPC dictionary with an "op".
 *
 * Client to daemon:
 *   ADD      id (int64, chosen by the client), behavior (int64, a CFNotificationSuspensionBehavior), optional name and
 *            object (strings; absent means any)
 *   REMOVE   id
 *   SUSPEND  suspended (bool): the client's process is suspended or not
 *   POST     name (string), optional object (string), optional userinfo (data: a binary property list),
 *            immediate (bool)
 * Daemon to client:
 *   DELIVER  ids (array of int64: the client's registrations that match), name, optional object and userinfo, as posted
 * HELLO is answered with an empty reply; a client uses it to find out whether the daemon is there.
 */

#ifndef __CFDISTRIBUTEDNOTIFICATION_PRIVATE_H__
#define __CFDISTRIBUTEDNOTIFICATION_PRIVATE_H__

#define CFDN_SERVICE_NAME "com.apple.distributed_notifications@Uv3"

#define CFDN_KEY_OP "op"
#define CFDN_KEY_ID "id"
#define CFDN_KEY_IDS "ids"
#define CFDN_KEY_NAME "name"
#define CFDN_KEY_OBJECT "object"
#define CFDN_KEY_BEHAVIOR "behavior"
#define CFDN_KEY_SUSPENDED "suspended"
#define CFDN_KEY_USERINFO "userinfo"
#define CFDN_KEY_IMMEDIATE "immediate"

enum {
	CFDN_OP_HELLO = 0,
	CFDN_OP_ADD = 1,
	CFDN_OP_REMOVE = 2,
	CFDN_OP_SUSPEND = 3,
	CFDN_OP_POST = 4,
	CFDN_OP_DELIVER = 5,
};

// Limits the daemon enforces on what a client sends.
#define CFDN_MAX_STRING 4096
#define CFDN_MAX_USERINFO (4 * 1024 * 1024)
#define CFDN_MAX_REGISTRATIONS 65536

// Whether a notification reaches a registration, once the name and object matched. While the process is suspended only
// registrations that ask for immediate delivery, and notifications posted for immediate delivery, get through.
//
// QUIRK: for a suspended process the registrations that ask to coalesce also get every notification at once, and the
// ones that ask to hold get none, neither while suspended nor after the process resumes; only "drop" behaves as
// documented. Documented behaviour (the notifications are held or combined and delivered on resume) is not what
// happens. Evidence (tier 2, black-box observation): plain processes on macOS 26.7.3 and 10.14.4 (x86_64 and i386),
// observer process suspended through CFNotificationCenterSetSuspended and NSDistributedNotificationCenter
// setSuspended:, notifications posted from a second process, five seconds of run loop after the resume.
// Test: distributed_notifications.m, suspension phases (test_quirk_suspended_coalesce_hold).
static inline int CFDN_ShouldDeliver(int suspended, int immediate, int behavior) {
	if (!suspended || immediate || behavior == 4) return 1;
	return behavior == 2;
}

#endif
