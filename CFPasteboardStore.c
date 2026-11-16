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

#include "CFPasteboardStore.h"
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFString.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	CFStringRef type;
	CFDataRef data;      // NULL while promised
	uint32_t flags;
	Boolean promised;
	Boolean visible;     // a promise that reads as flagged Promised
} CFPBFlavor;

typedef struct {
	CFPasteboardItemID id;
	CFPBFlavor *flavors;
	CFIndex count;
	CFIndex capacity;
} CFPBItem;

typedef struct {
	CFStringRef name;
	uint64_t changeCount;
	CFPBClient owner;
	CFPBClient creator;      // unique boards only
	Boolean unique;
	CFPBItem *items;
	CFIndex count;
	CFIndex capacity;
	CFPasteboardItemID nextItemID;
	uint64_t dataBytes;
	CFURLRef pasteLocation;
} CFPBBoard;

struct __CFPBStore {
	pthread_mutex_t lock;
	CFMutableDictionaryRef boards;   // name -> CFPBBoard* (stored as raw pointers)
	uint64_t initialCount;
	uint64_t totalBytes;     // data held by all boards together
	uint64_t totalFlavors;   // flavor entries of all boards together
	uint64_t totalItems;     // items of all boards together
};

#define STORE_LOCK(s) pthread_mutex_lock(&(s)->lock)
#define STORE_UNLOCK(s) pthread_mutex_unlock(&(s)->lock)

static Boolean nameIsValid(CFStringRef name) {
	if (name == NULL || CFGetTypeID(name) != CFStringGetTypeID()) return false;
	CFIndex length = CFStringGetLength(name);
	if (length == 0) return false;
	CFIndex bytes = 0;
	CFIndex converted = CFStringGetBytes(name, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, false, NULL, 0, &bytes);
	return converted == length && bytes <= CFPB_MAX_NAME_BYTES;
}

static Boolean flavorIsValid(CFStringRef flavor) {
	if (flavor == NULL || CFGetTypeID(flavor) != CFStringGetTypeID()) return false;
	CFIndex length = CFStringGetLength(flavor);
	if (length == 0) return false;
	CFIndex bytes = 0;
	CFIndex converted = CFStringGetBytes(flavor, CFRangeMake(0, length), kCFStringEncodingUTF8, 0, false, NULL, 0, &bytes);
	return converted == length && bytes <= CFPB_MAX_FLAVOR_BYTES;
}

static void flavorDestroy(CFPBFlavor *flavor) {
	CFRelease(flavor->type);
	if (flavor->data != NULL) CFRelease(flavor->data);
}

static void boardClear(CFPBStore *store, CFPBBoard *board) {
	for (CFIndex i = 0; i < board->count; ++i) {
		for (CFIndex k = 0; k < board->items[i].count; ++k) flavorDestroy(&board->items[i].flavors[k]);
		store->totalFlavors -= (uint64_t)board->items[i].count;
		free(board->items[i].flavors);
	}
	store->totalBytes -= board->dataBytes;
	store->totalItems -= (uint64_t)board->count;
	board->count = 0;
	board->dataBytes = 0;
	if (board->pasteLocation != NULL) {
		CFRelease(board->pasteLocation);
		board->pasteLocation = NULL;
	}
}

static void boardDestroy(CFPBStore *store, CFPBBoard *board) {
	boardClear(store, board);
	free(board->items);
	CFRelease(board->name);
	free(board);
}

// callers hold the lock
static CFPBBoard *boardFind(CFPBStore *store, CFStringRef name) {
	return (CFPBBoard *)CFDictionaryGetValue(store->boards, name);
}

static CFPBBoard *boardCreate(CFPBStore *store, CFStringRef name, Boolean unique, CFPBClient creator) {
	if (CFDictionaryGetCount(store->boards) >= CFPB_MAX_BOARDS) return NULL;
	CFPBBoard *board = calloc(1, sizeof(*board));
	if (board == NULL) return NULL;
	board->name = CFStringCreateCopy(kCFAllocatorSystemDefault, name);
	board->changeCount = store->initialCount;
	board->unique = unique;
	board->creator = creator;
	board->nextItemID = 0x10000;
	CFDictionarySetValue(store->boards, board->name, board);
	return board;
}

static CFPBItem *itemFind(CFPBBoard *board, CFPasteboardItemID id) {
	for (CFIndex i = 0; i < board->count; ++i) {
		if (board->items[i].id == id) return &board->items[i];
	}
	return NULL;
}

static CFPBItem *itemAppend(CFPBStore *store, CFPBBoard *board, CFPasteboardItemID id) {
	if (board->count >= CFPB_MAX_ITEMS || store->totalItems >= CFPB_MAX_TOTAL_ITEMS) return NULL;
	if (board->count == board->capacity) {
		CFIndex capacity = board->capacity ? board->capacity * 2 : 4;
		CFPBItem *grown = realloc(board->items, capacity * sizeof(CFPBItem));
		if (grown == NULL) return NULL;
		board->items = grown;
		board->capacity = capacity;
	}
	CFPBItem *item = &board->items[board->count++];
	store->totalItems++;
	memset(item, 0, sizeof(*item));
	item->id = id;
	return item;
}

static CFPBFlavor *flavorFind(CFPBItem *item, CFStringRef type) {
	for (CFIndex i = 0; i < item->count; ++i) {
		if (CFEqual(item->flavors[i].type, type)) return &item->flavors[i];
	}
	return NULL;
}

CFPBStore *_CFPBStoreCreate(uint64_t initialCount) {
	CFPBStore *store = calloc(1, sizeof(*store));
	if (store == NULL) return NULL;
	pthread_mutex_init(&store->lock, NULL);
	store->boards = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
	store->initialCount = initialCount;
	return store;
}

CFPasteboardStatus _CFPBStoreOpen(CFPBStore *store, CFStringRef name) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPasteboardStatus status = kCFPasteboardSuccess;
	if (boardFind(store, name) == NULL && boardCreate(store, name, false, NULL) == NULL) status = kCFPasteboardTooLarge;
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreCreateUnique(CFPBStore *store, CFPBClient creator, CFStringRef *name) {
	STORE_LOCK(store);
	CFPasteboardStatus status = kCFPasteboardTooLarge;
	for (int attempt = 0; attempt < 8; ++attempt) {
		uint64_t random = ((uint64_t)arc4random() << 32 | arc4random()) & 0xffffffffffffULL;
		CFStringRef candidate = CFStringCreateWithFormat(kCFAllocatorSystemDefault, NULL, CFSTR("CFPasteboardUnique-%012llx"), (unsigned long long)random);
		if (boardFind(store, candidate) == NULL) {
			if (boardCreate(store, candidate, true, creator) != NULL) {
				*name = candidate;
				status = kCFPasteboardSuccess;
			} else {
				CFRelease(candidate);
			}
			break;
		}
		CFRelease(candidate);
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreReleaseUnique(CFPBStore *store, CFStringRef name, CFPBClient client) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPasteboardStatus status = kCFPasteboardInvalid;
	CFPBBoard *board = boardFind(store, name);
	if (board != NULL && board->unique && board->creator == client) {
		CFDictionaryRemoveValue(store->boards, board->name);
		boardDestroy(store, board);
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreBegin(CFPBStore *store, CFStringRef name, CFPBClient client, uint64_t *newCount, CFPBClient *previousOwner) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	if (board == NULL) board = boardCreate(store, name, false, NULL);
	CFPasteboardStatus status = kCFPasteboardTooLarge;
	if (board != NULL) {
		boardClear(store, board);
		*previousOwner = board->owner;
		board->owner = client;
		*newCount = ++board->changeCount;
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreGetInfo(CFPBStore *store, CFStringRef name, uint64_t *count, CFIndex *itemCount, CFPBClient *owner) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	if (board == NULL) board = boardCreate(store, name, false, NULL);
	CFPasteboardStatus status = kCFPasteboardTooLarge;
	if (board != NULL) {
		if (count) *count = board->changeCount;
		if (itemCount) *itemCount = board->count;
		if (owner) *owner = board->owner;
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreItemAt(CFPBStore *store, CFStringRef name, CFIndex index, CFPasteboardItemID *item) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPasteboardStatus status = kCFPasteboardBadIndex;
	if (board != NULL && index >= 0 && index < board->count) {
		*item = board->items[index].id;
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreAddItem(CFPBStore *store, CFStringRef name, CFPBClient client, CFPasteboardItemID *item) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPasteboardStatus status = kCFPasteboardNotOwner;
	if (board != NULL && board->owner == client) {
		while (itemFind(board, board->nextItemID) != NULL) board->nextItemID++;
		CFPBItem *added = itemAppend(store, board, board->nextItemID);
		if (added != NULL) {
			*item = board->nextItemID++;
			status = kCFPasteboardSuccess;
		} else {
			status = kCFPasteboardTooLarge;
		}
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreCopyFlavors(CFPBStore *store, CFStringRef name, CFPasteboardItemID item, CFArrayRef *flavors) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPBItem *found = board ? itemFind(board, item) : NULL;
	CFPasteboardStatus status = kCFPasteboardBadItem;
	if (found != NULL) {
		CFMutableArrayRef types = CFArrayCreateMutable(kCFAllocatorSystemDefault, found->count, &kCFTypeArrayCallBacks);
		for (CFIndex i = 0; i < found->count; ++i) CFArrayAppendValue(types, found->flavors[i].type);
		*flavors = types;
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreGetFlavor(CFPBStore *store, CFStringRef name, CFPasteboardItemID item, CFStringRef flavor, uint32_t *flags, Boolean *promised, CFDataRef *data) {
	if (!nameIsValid(name) || !flavorIsValid(flavor)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPBItem *found = board ? itemFind(board, item) : NULL;
	CFPasteboardStatus status = kCFPasteboardBadItem;
	if (found != NULL) {
		CFPBFlavor *entry = flavorFind(found, flavor);
		status = kCFPasteboardBadFlavor;
		if (entry != NULL) {
			if (flags) *flags = entry->flags | (entry->promised && entry->visible ? kCFPasteboardFlavorPromised : 0);
			if (promised) *promised = entry->promised;
			if (data) *data = entry->data ? CFRetain(entry->data) : NULL;
			status = kCFPasteboardSuccess;
		}
	}
	STORE_UNLOCK(store);
	return status;
}

static CFIndex promisesLeftLocked(CFPBBoard *board) {
	CFIndex left = 0;
	for (CFIndex i = 0; i < board->count; ++i) {
		for (CFIndex k = 0; k < board->items[i].count; ++k) {
			if (board->items[i].flavors[k].promised) left++;
		}
	}
	return left;
}

CFPasteboardStatus _CFPBStoreSetFlavor(CFPBStore *store, CFStringRef name, CFPBClient client, CFPasteboardItemID item, CFStringRef flavor,
		CFDataRef data, uint32_t flags, Boolean promised, uint64_t *changeCount, Boolean *hadPromisesLeft) {
	if (!nameIsValid(name) || !flavorIsValid(flavor)) return kCFPasteboardInvalid;
	if (data != NULL && CFGetTypeID(data) != CFDataGetTypeID()) return kCFPasteboardInvalid;
	if (promised && data != NULL) return kCFPasteboardInvalid;
	uint64_t length = data ? (uint64_t)CFDataGetLength(data) : 0;
	if (length > CFPB_MAX_FLAVOR_DATA) return kCFPasteboardTooLarge;
	Boolean visible = (flags & kCFPasteboardFlavorPromiseVisible) != 0;
	flags &= ~((uint32_t)kCFPasteboardFlavorPromised | kCFPasteboardFlavorPromiseVisible);

	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPasteboardStatus status = kCFPasteboardNotOwner;
	if (board != NULL && board->owner == client && client != NULL) {
		CFPBItem *found = itemFind(board, item);
		if (found == NULL) found = itemAppend(store, board, item);
		CFPBFlavor *entry = found ? flavorFind(found, flavor) : NULL;
		uint64_t previous = (entry && entry->data) ? (uint64_t)CFDataGetLength(entry->data) : 0;
		if (found == NULL) {
			status = kCFPasteboardTooLarge;
		} else if (board->dataBytes - previous + length > CFPB_MAX_BOARD_DATA) {
			status = kCFPasteboardTooLarge;
		} else if (entry == NULL && found->count >= CFPB_MAX_FLAVORS) {
			status = kCFPasteboardTooLarge;
		} else if (store->totalBytes - previous + length > CFPB_MAX_TOTAL_DATA || (entry == NULL && store->totalFlavors >= CFPB_MAX_TOTAL_FLAVORS)) {
			status = kCFPasteboardTooLarge;
		} else {
			if (entry == NULL) {
				if (found->count == found->capacity) {
					CFIndex capacity = found->capacity ? found->capacity * 2 : 4;
					CFPBFlavor *grown = realloc(found->flavors, capacity * sizeof(CFPBFlavor));
					if (grown == NULL) { STORE_UNLOCK(store); return kCFPasteboardTooLarge; }
					found->flavors = grown;
					found->capacity = capacity;
				}
				entry = &found->flavors[found->count++];
				store->totalFlavors++;
				memset(entry, 0, sizeof(*entry));
				entry->type = CFStringCreateCopy(kCFAllocatorSystemDefault, flavor);
			} else if (entry->data != NULL) {
				CFRelease(entry->data);
				entry->data = NULL;
			}
			board->dataBytes = board->dataBytes - previous + length;
			store->totalBytes = store->totalBytes - previous + length;
			entry->data = data ? CFDataCreateCopy(kCFAllocatorSystemDefault, data) : (promised ? NULL : CFDataCreate(kCFAllocatorSystemDefault, NULL, 0));
			entry->flags = flags;
			entry->promised = promised;
			entry->visible = promised && visible;
			status = kCFPasteboardSuccess;
		}
		if (hadPromisesLeft) *hadPromisesLeft = promisesLeftLocked(board) > 0;
		if (changeCount) *changeCount = board->changeCount;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStorePromisesLeft(CFPBStore *store, CFStringRef name, CFIndex *count) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	*count = board ? promisesLeftLocked(board) : 0;
	STORE_UNLOCK(store);
	return kCFPasteboardSuccess;
}

CFPasteboardStatus _CFPBStoreSetPasteLocation(CFPBStore *store, CFStringRef name, CFURLRef location) {
	if (!nameIsValid(name) || location == NULL || CFGetTypeID(location) != CFURLGetTypeID()) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	CFPasteboardStatus status = kCFPasteboardInvalid;
	if (board != NULL) {
		if (board->pasteLocation != NULL) CFRelease(board->pasteLocation);
		board->pasteLocation = CFRetain(location);
		status = kCFPasteboardSuccess;
	}
	STORE_UNLOCK(store);
	return status;
}

CFPasteboardStatus _CFPBStoreCopyPasteLocation(CFPBStore *store, CFStringRef name, CFURLRef *location) {
	if (!nameIsValid(name)) return kCFPasteboardInvalid;
	STORE_LOCK(store);
	CFPBBoard *board = boardFind(store, name);
	*location = (board && board->pasteLocation) ? CFRetain(board->pasteLocation) : NULL;
	STORE_UNLOCK(store);
	return kCFPasteboardSuccess;
}

void _CFPBStoreClientGone(CFPBStore *store, CFPBClient client) {
	STORE_LOCK(store);
	CFIndex count = CFDictionaryGetCount(store->boards);
	CFPBBoard **boards = malloc((count ? count : 1) * sizeof(*boards));
	if (boards != NULL) {
		CFDictionaryGetKeysAndValues(store->boards, NULL, (const void **)boards);
		for (CFIndex i = 0; i < count; ++i) {
			CFPBBoard *board = boards[i];
			if (board->unique && board->creator == client) {
				CFDictionaryRemoveValue(store->boards, board->name);
				boardDestroy(store, board);
			} else if (board->owner == client) {
				// promises of a departed owner can never be kept: drop those flavors
				for (CFIndex a = 0; a < board->count; ++a) {
					CFPBItem *item = &board->items[a];
					for (CFIndex b = 0; b < item->count;) {
						if (item->flavors[b].promised) {
							flavorDestroy(&item->flavors[b]);
							store->totalFlavors--;
							memmove(&item->flavors[b], &item->flavors[b + 1], (item->count - b - 1) * sizeof(CFPBFlavor));
							item->count--;
						} else {
							b++;
						}
					}
				}
				board->owner = NULL;
			}
		}
		free(boards);
	}
	STORE_UNLOCK(store);
}
