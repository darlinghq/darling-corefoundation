#import <Foundation/NSObject.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#include <CoreFoundation/CFFileSecurity.h>
#include <CoreFoundation/CFUUID.h>
#include <string.h>

// Backing object for CFFileSecurityRef / NSFileSecurity (toll-free bridged). The POSIX
// owner, group and mode and the owner and group UUIDs are stored; access control lists
// are not supported.
@interface NSFileSecurity : NSObject <NSCopying, NSSecureCoding>
{
@public
	uid_t _owner;
	gid_t _group;
	mode_t _mode;
	BOOL _hasOwner, _hasGroup, _hasMode;
	CFUUIDRef _ownerUUID, _groupUUID;
}
@end

// The class of the objects CFFileSecurityCreate returns.
@interface __NSFileSecurity : NSFileSecurity
@end

// Keyed archive layout: NS.filesec holds a 72-byte little-endian record: a flags word at
// offset 0, owner at 8, group at 16, mode at 24, owner UUID at 32 and group UUID at 48,
// the rest zero. The flags say which fields are set (an ACL, flag 0x20, is followed by
// its text after the record; it is ignored when decoding).
enum {
	kFileSecurityFlagOwner = 0x01,
	kFileSecurityFlagGroup = 0x02,
	kFileSecurityFlagOwnerUUID = 0x04,
	kFileSecurityFlagGroupUUID = 0x08,
	kFileSecurityFlagMode = 0x10,
	kFileSecurityFlagACL = 0x20,
};
enum { kFileSecurityRecordSize = 72 };

static void PutLE32(uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

static uint32_t GetLE32(const uint8_t *p)
{
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void PutUUID(uint8_t *p, CFUUIDRef uuid)
{
	CFUUIDBytes b = CFUUIDGetUUIDBytes(uuid);
	memcpy(p, &b, 16);
}

static CFUUIDRef CreateUUID(const uint8_t *p)
{
	CFUUIDBytes b;
	memcpy(&b, p, 16);
	return CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, b);
}

@implementation NSFileSecurity

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)dealloc
{
	if (_ownerUUID) CFRelease(_ownerUUID);
	if (_groupUUID) CFRelease(_groupUUID);
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	NSFileSecurity *copy = [[[self class] allocWithZone:zone] init];
	copy->_owner = _owner;
	copy->_group = _group;
	copy->_mode = _mode;
	copy->_hasOwner = _hasOwner;
	copy->_hasGroup = _hasGroup;
	copy->_hasMode = _hasMode;
	copy->_ownerUUID = _ownerUUID ? (CFUUIDRef)CFRetain(_ownerUUID) : NULL;
	copy->_groupUUID = _groupUUID ? (CFUUIDRef)CFRetain(_groupUUID) : NULL;
	return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (![coder allowsKeyedCoding])
	{
		[NSException raise:NSInvalidArgumentException format:@"NSFileSecurity cannot be encoded by non-keyed archivers"];
		return;
	}
	uint8_t record[kFileSecurityRecordSize];
	memset(record, 0, sizeof(record));
	uint32_t flags = 0;
	if (_hasOwner) { flags |= kFileSecurityFlagOwner; PutLE32(record + 8, (uint32_t)_owner); }
	if (_hasGroup) { flags |= kFileSecurityFlagGroup; PutLE32(record + 16, (uint32_t)_group); }
	if (_hasMode) { flags |= kFileSecurityFlagMode; PutLE32(record + 24, (uint32_t)_mode); }
	if (_ownerUUID) { flags |= kFileSecurityFlagOwnerUUID; PutUUID(record + 32, _ownerUUID); }
	if (_groupUUID) { flags |= kFileSecurityFlagGroupUUID; PutUUID(record + 48, _groupUUID); }
	PutLE32(record, flags);
	[coder encodeBytes:record length:sizeof(record) forKey:@"NS.filesec"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	NSUInteger length = 0;
	const uint8_t *record = [coder allowsKeyedCoding] ? [coder decodeBytesForKey:@"NS.filesec" returnedLength:&length] : NULL;
	if (record == NULL || length < kFileSecurityRecordSize)
	{
		[self release];
		return nil;
	}
	self = [self init];
	if (self == nil)
	{
		return nil;
	}
	uint32_t flags = GetLE32(record);
	if (flags & kFileSecurityFlagOwner) { _owner = (uid_t)GetLE32(record + 8); _hasOwner = YES; }
	if (flags & kFileSecurityFlagGroup) { _group = (gid_t)GetLE32(record + 16); _hasGroup = YES; }
	if (flags & kFileSecurityFlagMode) { _mode = (mode_t)(GetLE32(record + 24) & 0xffff); _hasMode = YES; }
	if (flags & kFileSecurityFlagOwnerUUID) _ownerUUID = CreateUUID(record + 32);
	if (flags & kFileSecurityFlagGroupUUID) _groupUUID = CreateUUID(record + 48);
	return self;
}

@end

@implementation __NSFileSecurity
@end

#define SEC(ref) ((NSFileSecurity *)(id)(ref))

static void SetUUID(CFUUIDRef *slot, CFUUIDRef uuid);

CFFileSecurityRef CFFileSecurityCreate(CFAllocatorRef allocator)
{
	return (CFFileSecurityRef)[[__NSFileSecurity alloc] init];
}

CFFileSecurityRef CFFileSecurityCreateCopy(CFAllocatorRef allocator, CFFileSecurityRef fileSec)
{
	return fileSec ? (CFFileSecurityRef)[SEC(fileSec) copy] : NULL;
}

Boolean CFFileSecurityGetOwner(CFFileSecurityRef fileSec, uid_t *owner)
{
	if (!fileSec || !SEC(fileSec)->_hasOwner) return false;
	if (owner) *owner = SEC(fileSec)->_owner;
	return true;
}

Boolean CFFileSecuritySetOwner(CFFileSecurityRef fileSec, uid_t owner)
{
	if (!fileSec) return false;
	SEC(fileSec)->_owner = owner;
	SEC(fileSec)->_hasOwner = YES;
	return true;
}

Boolean CFFileSecurityGetGroup(CFFileSecurityRef fileSec, gid_t *group)
{
	if (!fileSec || !SEC(fileSec)->_hasGroup) return false;
	if (group) *group = SEC(fileSec)->_group;
	return true;
}

Boolean CFFileSecuritySetGroup(CFFileSecurityRef fileSec, gid_t group)
{
	if (!fileSec) return false;
	SEC(fileSec)->_group = group;
	SEC(fileSec)->_hasGroup = YES;
	return true;
}

Boolean CFFileSecurityGetMode(CFFileSecurityRef fileSec, mode_t *mode)
{
	if (!fileSec || !SEC(fileSec)->_hasMode) return false;
	if (mode) *mode = SEC(fileSec)->_mode;
	return true;
}

Boolean CFFileSecuritySetMode(CFFileSecurityRef fileSec, mode_t mode)
{
	if (!fileSec) return false;
	SEC(fileSec)->_mode = mode & 0xffff;
	SEC(fileSec)->_hasMode = YES;
	return true;
}

Boolean CFFileSecurityClearProperties(CFFileSecurityRef fileSec, CFOptionFlags clearPropertyMask)
{
	if (!fileSec) return false;
	if (clearPropertyMask & kCFFileSecurityClearOwner) SEC(fileSec)->_hasOwner = NO;
	if (clearPropertyMask & kCFFileSecurityClearGroup) SEC(fileSec)->_hasGroup = NO;
	if (clearPropertyMask & kCFFileSecurityClearMode) SEC(fileSec)->_hasMode = NO;
	if (clearPropertyMask & kCFFileSecurityClearOwnerUUID) SetUUID(&SEC(fileSec)->_ownerUUID, NULL);
	if (clearPropertyMask & kCFFileSecurityClearGroupUUID) SetUUID(&SEC(fileSec)->_groupUUID, NULL);
	return true;
}

static void SetUUID(CFUUIDRef *slot, CFUUIDRef uuid)
{
	CFUUIDRef old = *slot;
	*slot = uuid ? (CFUUIDRef)CFRetain(uuid) : NULL;
	if (old) CFRelease(old);
}

static Boolean CopyUUID(CFUUIDRef uuid, CFUUIDRef *out)
{
	if (!uuid) return false;
	if (out) *out = (CFUUIDRef)CFRetain(uuid);
	return true;
}

Boolean CFFileSecurityCopyOwnerUUID(CFFileSecurityRef fileSec, CFUUIDRef *ownerUUID) { return fileSec && CopyUUID(SEC(fileSec)->_ownerUUID, ownerUUID); }
Boolean CFFileSecuritySetOwnerUUID(CFFileSecurityRef fileSec, CFUUIDRef ownerUUID) { if (!fileSec) return false; SetUUID(&SEC(fileSec)->_ownerUUID, ownerUUID); return true; }
Boolean CFFileSecurityCopyGroupUUID(CFFileSecurityRef fileSec, CFUUIDRef *groupUUID) { return fileSec && CopyUUID(SEC(fileSec)->_groupUUID, groupUUID); }
Boolean CFFileSecuritySetGroupUUID(CFFileSecurityRef fileSec, CFUUIDRef groupUUID) { if (!fileSec) return false; SetUUID(&SEC(fileSec)->_groupUUID, groupUUID); return true; }
// Access control lists are not represented.
Boolean CFFileSecurityCopyAccessControlList(CFFileSecurityRef fileSec, acl_t *accessControlList) { return false; }
Boolean CFFileSecuritySetAccessControlList(CFFileSecurityRef fileSec, acl_t accessControlList) { return false; }
