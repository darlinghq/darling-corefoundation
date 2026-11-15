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

// The request and reply messages between a CFPasteboard client and the board service. A request is an XPC
// dictionary with an "op" and the arguments of that operation; a reply carries "status" (a CFPasteboardStatus) and
// the results. The same handler answers requests that arrive over the Mach service and the ones a process makes to
// its own in-process store.

#ifndef __CFPASTEBOARDPROTOCOL_H__
#define __CFPASTEBOARDPROTOCOL_H__

#include "CFPasteboardStore.h"
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>

CF_EXTERN_C_BEGIN

#ifndef CFPB_SERVICE_NAME
#define CFPB_SERVICE_NAME "com.apple.pasteboard.1"
#endif

enum {
	CFPB_OP_HELLO = 0,
	CFPB_OP_OPEN,
	CFPB_OP_UNIQUE,
	CFPB_OP_RELEASE,
	CFPB_OP_BEGIN,
	CFPB_OP_INFO,
	CFPB_OP_ITEM_AT,
	CFPB_OP_ADD_ITEM,
	CFPB_OP_FLAVORS,
	CFPB_OP_FLAVOR_INFO,
	CFPB_OP_DATA,
	CFPB_OP_SET,
	CFPB_OP_SET_LOCATION,
	CFPB_OP_GET_LOCATION,
	CFPB_OP_LAST
};

// request keys
#define CFPB_KEY_OP "op"           // int64
#define CFPB_KEY_NAME "name"       // string
#define CFPB_KEY_INDEX "index"     // int64
#define CFPB_KEY_ITEM "item"       // uint64
#define CFPB_KEY_FLAVOR "flavor"   // string
#define CFPB_KEY_DATA "data"       // data; absent for a promise or empty data
#define CFPB_KEY_FLAGS "flags"     // uint64
#define CFPB_KEY_PROMISED "promised"   // bool
#define CFPB_KEY_RESOLVE "resolve" // bool: DATA asks the promise owner for the data
#define CFPB_KEY_LOCATION "location"   // string (URL)
// reply keys
#define CFPB_KEY_STATUS "status"   // int64
#define CFPB_KEY_COUNT "count"     // uint64: change count
#define CFPB_KEY_ITEMS "items"     // int64: item count
#define CFPB_KEY_OWNED "owned"     // bool: the requester owns the generation
#define CFPB_KEY_FLAVORS "flavors" // array of strings
#define CFPB_KEY_SELF "self"       // bool: the data is promised by the requester itself
#define CFPB_KEY_LEFT "left"       // int64: promises still unresolved
#define CFPB_KEY_PREVIOUS_SELF "previousself"  // bool: BEGIN ended a generation the requester owned
#define CFPB_KEY_NAME_RESULT "name"

// messages the service sends to a client
#define CFPB_OP_PUSH_RESOLVE 100   // name, count not needed: item, flavor; the client answers with status
#define CFPB_OP_PUSH_OWNER_LOST 101

typedef struct {
	// Asks the owner of a generation to supply a promised flavor. Calls done(status) once, from any thread. NULL when
	// every client is the process itself.
	void (^askOwner)(CFPBClient owner, CFStringRef name, CFPasteboardItemID item, CFStringRef flavor, void (^done)(CFPasteboardStatus status));
	// Tells a client its generation of a board ended. May be NULL.
	void (^ownerLost)(CFPBClient previousOwner, CFStringRef name);
} CFPBServiceHooks;

// Answers one request on behalf of client. complete is called exactly once, possibly after the function returned, with
// a reply the caller may send. All fields of the request are validated here.
CF_PRIVATE void _CFPBServiceHandle(CFPBStore *store, CFPBClient client, xpc_object_t request, const CFPBServiceHooks *hooks,
	void (^complete)(xpc_object_t reply));

CF_EXTERN_C_END

#endif
