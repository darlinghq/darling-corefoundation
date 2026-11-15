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
 * Private interface of CoreFoundation's pasteboard store, used by the Pasteboard Manager (HIServices) and by
 * NSPasteboard (AppKit). It is not a public API: the names follow the ones CoreFoundation exports on macOS for the
 * operations Darling's own frameworks need, the signatures are Darling's.
 *
 * Model. A pasteboard is a named board holding an ordered list of items; an item is a set of flavors (a type name,
 * usually a UTI, with data, flags and possibly a promise of data). A board has a change count that grows by one
 * every time its contents are replaced (CFPasteboardBeginGeneration). The process that began the current
 * generation owns it and is the only one that may add items and flavors to it, until the next generation begins.
 *
 * Where a board lives. A process-wide choice made when a CFPasteboardRef is created:
 *  - a board that a host bridge handles (see below) lives in the process and the bridge mirrors it to the host;
 *  - any other board lives in the user's pboard service (Mach service com.apple.pasteboard.1), which keeps the data
 *    for all of the user's processes;
 *  - if the service cannot be reached the board lives in the process.
 * The behaviour is the same in all three cases.
 *
 * Threading. All functions may be called from any thread. Promise callbacks run on an unspecified thread, without
 * any internal lock held, and may call back into this interface for the same pasteboard.
 */

#ifndef __COREFOUNDATION_CFPASTEBOARD_PRIVATE__
#define __COREFOUNDATION_CFPASTEBOARD_PRIVATE__

#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFURL.h>
#include <xpc/xpc.h>

CF_EXTERN_C_BEGIN

typedef struct __CFPasteboard *CFPasteboardRef;

/* Identifies an item within one board. Callers may pick the value (the Pasteboard Manager does); CFPasteboardAddItem
 * hands out a value that is not in use. */
typedef uint64_t CFPasteboardItemID;

typedef SInt32 CFPasteboardStatus;
enum {
	kCFPasteboardSuccess = 0,
	kCFPasteboardBadItem = 1,        /* no such item */
	kCFPasteboardBadFlavor = 2,      /* the item has no such flavor */
	kCFPasteboardBadIndex = 3,       /* item index out of range */
	kCFPasteboardNotOwner = 4,       /* the caller did not begin the current generation */
	kCFPasteboardNoProvider = 5,     /* a promise was made without a provider, or the provider did not supply data */
	kCFPasteboardTooLarge = 6,       /* a size limit of the store was exceeded */
	kCFPasteboardInvalid = 7,        /* bad argument */
	kCFPasteboardUnavailable = 8     /* the service did not answer */
};

/* Flavor flags. The values are those of the Pasteboard Manager's flavor flags, which the store keeps without
 * interpreting them; the one exception is kCFPasteboardFlavorPromised, which the store sets by itself while the data
 * of a flavor is only promised. */
typedef CF_OPTIONS(uint32_t, CFPasteboardFlavorFlags) {
	kCFPasteboardFlavorNoFlags = 0,
	kCFPasteboardFlavorSenderOnly = (1 << 0),
	kCFPasteboardFlavorSenderTranslated = (1 << 1),
	kCFPasteboardFlavorNotSaved = (1 << 2),
	kCFPasteboardFlavorRequestOnly = (1 << 3),
	kCFPasteboardFlavorSystemTranslated = (1 << 8),
	kCFPasteboardFlavorPromised = (1 << 9)
};

/* The names of the standard boards. Other names (including the font and ruler boards of NSPasteboard) are boards of
 * their own. */
CF_EXPORT const CFStringRef kCFPasteboardGeneral;   /* "Apple CFPasteboard general" */
CF_EXPORT const CFStringRef kCFPasteboardFind;      /* "Apple CFPasteboard find" */
CF_EXPORT const CFStringRef __kCFPasteboardDrag;    /* "Apple CFPasteboard drag" */

CF_EXPORT CFTypeID CFPasteboardGetTypeID(void);

/* Returns the board with the given name, creating it on first use. Names are at most 255 bytes in UTF-8. NULL (or
 * an empty string) is not a name: use CFPasteboardCreateUnique. Returns NULL for an invalid name. */
CF_EXPORT CFPasteboardRef CFPasteboardCreate(CFAllocatorRef allocator, CFStringRef name);

/* Creates a board with a name nobody else has ("CFPasteboardUnique-" and 12 hex digits). A unique board is
 * dropped when the creating process exits or when CFPasteboardReleaseGlobally is called for it. */
CF_EXPORT CFPasteboardRef CFPasteboardCreateUnique(CFAllocatorRef allocator);
CF_EXPORT void CFPasteboardReleaseGlobally(CFPasteboardRef pasteboard);

CF_EXPORT CFStringRef CFPasteboardCopyName(CFPasteboardRef pasteboard);

/* Number of times the contents of the board were replaced, as seen by every process. Returns 0 if the board cannot
 * be reached. */
CF_EXPORT CFIndex CFPasteboardGetChangeCount(CFPasteboardRef pasteboard);

/* Drops the contents of the board and makes the caller its owner. Returns the new change count, or 0 on failure. */
CF_EXPORT CFIndex CFPasteboardBeginGeneration(CFPasteboardRef pasteboard);

CF_EXPORT CFPasteboardStatus CFPasteboardGetItemCount(CFPasteboardRef pasteboard, CFIndex *count);
/* index is 0-based */
CF_EXPORT CFPasteboardStatus CFPasteboardGetItemAtIndex(CFPasteboardRef pasteboard, CFIndex index, CFPasteboardItemID *item);
/* Adds an empty item that has an identifier not used by any other item of the board. Caller must own the generation. */
CF_EXPORT CFPasteboardStatus CFPasteboardAddItem(CFPasteboardRef pasteboard, CFPasteboardItemID *item);

/* The flavor types of the item in the order they were added, as an array of CFStringRef. */
CF_EXPORT CFPasteboardStatus CFPasteboardCopyFlavorsForItem(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFArrayRef *flavors);
CF_EXPORT CFPasteboardStatus CFPasteboardGetDataFlags(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags *flags);
CF_EXPORT Boolean CFPasteboardIsDataPromised(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor);

/* Returns the data of a flavor. If the data is promised, the provider of the promise is asked for it first (in the
 * process that owns the generation); *data is NULL if the provider did not supply any (the status is then
 * kCFPasteboardNoProvider). On success *data is retained. */
CF_EXPORT CFPasteboardStatus CFPasteboardCopyData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef *data);

/* Adds the flavor to the item, creating the item if needed, or replaces the data and flags of an existing flavor.
 * Caller must own the generation. Does not change the change count. */
CF_EXPORT CFPasteboardStatus CFPasteboardSetData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef data, CFPasteboardFlavorFlags flags);

/* Callbacks of the party that promised data. Any may be NULL except provide. */
typedef struct {
	CFIndex version;   /* 0 */
	/* Supplies the data of the flavor by calling CFPasteboardSetData; returns kCFPasteboardSuccess if it did. */
	CFPasteboardStatus (*provide)(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, void *info);
	/* Called once when no promise of the generation is unresolved any more. */
	void (*allProvided)(CFPasteboardRef pasteboard, void *info);
	/* Called when the generation ended (another generation began, from here or elsewhere) while the provider was
	 * still registered. Unresolved promises are gone then. */
	void (*ownerChanged)(CFPasteboardRef pasteboard, void *info);
	/* Called when the provider is dropped, last. */
	void (*release)(void *info);
} CFPasteboardProviderCallbacks;

/* Adds a flavor without data to the item and records that provider will supply it when somebody reads it. All
 * promises of a generation share one provider: a later call with a different info replaces it. The provider's
 * lifetime ends with the generation. Caller must own the generation. */
CF_EXPORT CFPasteboardStatus CFPasteboardPromiseData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFPasteboardFlavorFlags flags,
	const CFPasteboardProviderCallbacks *provider, void *info);

/* Asks the provider for every unresolved promise of the current generation that this process made. */
CF_EXPORT CFPasteboardStatus CFPasteboardResolveAllPromisedData(CFPasteboardRef pasteboard);

/* The location a receiver pasted a file promise to (see the Pasteboard Manager's paste location calls). Kept with the
 * current generation. */
CF_EXPORT CFPasteboardStatus CFPasteboardSetPasteLocation(CFPasteboardRef pasteboard, CFURLRef location);
CF_EXPORT CFPasteboardStatus CFPasteboardCopyPasteLocation(CFPasteboardRef pasteboard, CFURLRef *location);

/* Host bridge. A GUI backend that has access to the host's clipboard registers once, early, before the process
 * first creates the general or the drag board; those two boards then live in the process and the bridge mirrors
 * them. Boards that already exist keep where they live. */
typedef struct {
	CFIndex version;   /* 0 */
	/* A bridged board was changed by this process (a generation began, or items or flavors were added). The bridge
	 * reads the board through this interface; it should do its work later or on another thread rather than inside
	 * the call, since more additions may follow. */
	void (*boardChanged)(CFStringRef name, CFPasteboardRef pasteboard, void *info);
	/* Supplies a flavor that CFPasteboardHostBridgeReplaceContents listed without data (a lazily transferred
	 * host selection). Returns a retained CFData, or NULL. itemIndex is 0-based. */
	CFDataRef (*copyData)(CFStringRef name, CFIndex itemIndex, CFStringRef flavor, void *info);
	void *info;
} CFPasteboardHostBridgeCallbacks;

/* Returns false if a bridge was registered already. The callbacks are copied. */
CF_EXPORT Boolean CFPasteboardRegisterHostBridge(const CFPasteboardHostBridgeCallbacks *callbacks);

/* The host's clipboard changed: replaces the contents of the bridged board by the given items. items is an array of
 * dictionaries mapping a flavor type (CFString) to its data (CFData), or to kCFNull when the data is to be fetched
 * with copyData on demand. Begins a new generation. Returns the change count, or 0 on failure. */
CF_EXPORT CFIndex CFPasteboardHostBridgeReplaceContents(CFStringRef name, CFArrayRef items);

/* Entry point of the pboard service: serves the user's boards on the Mach service and does not return. */
CF_EXPORT void __CFPasteboardRunService(void);

/* For tests: starts a service inside the calling process on an anonymous listener and returns an endpoint to it,
 * and makes this process's pasteboards use the service behind an endpoint. The latter must be called before the
 * first pasteboard is created, and only once. */
CF_EXPORT xpc_endpoint_t __CFPasteboardStartInProcessService(void);
CF_EXPORT void __CFPasteboardAdoptServiceEndpoint(xpc_endpoint_t endpoint);

CF_EXTERN_C_END

#endif
