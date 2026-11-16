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

// The board store behind CFPasteboard: named boards of items and flavors, change counts, generation owners. The
// same code runs inside a process (for boards a host bridge handles, or when no service is reachable) and inside the
// pboard service. It knows nothing about messages or promise providers; callers identify themselves by an opaque
// client token. The functions take the store's lock themselves.

#ifndef __CFPASTEBOARDSTORE_H__
#define __CFPASTEBOARDSTORE_H__

#include <CoreFoundation/CFPasteboard_Private.h>

CF_EXTERN_C_BEGIN

// Limits (all are enforced by the store, which also serves untrusted peers)
#define CFPB_MAX_NAME_BYTES 255
#define CFPB_MAX_FLAVOR_BYTES 255
#define CFPB_MAX_BOARDS 4096
#define CFPB_MAX_ITEMS 4096
#define CFPB_MAX_FLAVORS 512
#define CFPB_MAX_FLAVOR_DATA ((uint64_t)256 << 20)
#define CFPB_MAX_BOARD_DATA ((uint64_t)1024 << 20)
// All boards together: what the service holds for one user stays bounded however many boards and flavors are made
#define CFPB_MAX_TOTAL_DATA ((uint64_t)2048 << 20)
#define CFPB_MAX_TOTAL_FLAVORS ((uint64_t)262144)
#define CFPB_MAX_TOTAL_ITEMS ((uint64_t)65536)

typedef const void *CFPBClient;
typedef struct __CFPBStore CFPBStore;

CF_PRIVATE CFPBStore *_CFPBStoreCreate(uint64_t initialCount);

// Opens (creates on first use) a named board. The creator of a board is remembered only for unique boards.
CF_PRIVATE CFPasteboardStatus _CFPBStoreOpen(CFPBStore *store, CFStringRef name);
// Creates a board with a fresh unique name; *name is returned retained.
CF_PRIVATE CFPasteboardStatus _CFPBStoreCreateUnique(CFPBStore *store, CFPBClient creator, CFStringRef *name);
// Drops a unique board; only its creator may.
CF_PRIVATE CFPasteboardStatus _CFPBStoreReleaseUnique(CFPBStore *store, CFStringRef name, CFPBClient client);

// Clears the board and makes client its owner. *previousOwner is the owner of the generation that ended (NULL if none).
CF_PRIVATE CFPasteboardStatus _CFPBStoreBegin(CFPBStore *store, CFStringRef name, CFPBClient client, uint64_t *newCount, CFPBClient *previousOwner);
CF_PRIVATE CFPasteboardStatus _CFPBStoreGetInfo(CFPBStore *store, CFStringRef name, uint64_t *count, CFIndex *itemCount, CFPBClient *owner);
CF_PRIVATE CFPasteboardStatus _CFPBStoreItemAt(CFPBStore *store, CFStringRef name, CFIndex index, CFPasteboardItemID *item);
CF_PRIVATE CFPasteboardStatus _CFPBStoreAddItem(CFPBStore *store, CFStringRef name, CFPBClient client, CFPasteboardItemID *item);
CF_PRIVATE CFPasteboardStatus _CFPBStoreCopyFlavors(CFPBStore *store, CFStringRef name, CFPasteboardItemID item, CFArrayRef *flavors);
// *data is retained and NULL while the flavor is promised. *flags carries the Promised bit only for a promise made
// visible (kCFPasteboardFlavorPromiseVisible); *promised is set for every promise.
CF_PRIVATE CFPasteboardStatus _CFPBStoreGetFlavor(CFPBStore *store, CFStringRef name, CFPasteboardItemID item, CFStringRef flavor,
	uint32_t *flags, Boolean *promised, CFDataRef *data);
// data NULL with promised false is empty data; with promised true it is a promise
CF_PRIVATE CFPasteboardStatus _CFPBStoreSetFlavor(CFPBStore *store, CFStringRef name, CFPBClient client, CFPasteboardItemID item, CFStringRef flavor,
	CFDataRef data, uint32_t flags, Boolean promised, uint64_t *changeCount, Boolean *hadPromisesLeft);
// The number of flavors still promised in the current generation
CF_PRIVATE CFPasteboardStatus _CFPBStorePromisesLeft(CFPBStore *store, CFStringRef name, CFIndex *count);
CF_PRIVATE CFPasteboardStatus _CFPBStoreSetPasteLocation(CFPBStore *store, CFStringRef name, CFURLRef location);
CF_PRIVATE CFPasteboardStatus _CFPBStoreCopyPasteLocation(CFPBStore *store, CFStringRef name, CFURLRef *location);

// A client is gone: its unique boards are dropped, the boards it owned lose their promised flavors and their owner.
CF_PRIVATE void _CFPBStoreClientGone(CFPBStore *store, CFPBClient client);

CF_EXTERN_C_END

#endif
