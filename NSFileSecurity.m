#import <Foundation/NSObject.h>
#include <CoreFoundation/CFFileSecurity.h>

// Backing object for CFFileSecurityRef / NSFileSecurity (toll-free bridged). Only the POSIX
// owner, group and mode are stored; UUIDs and ACLs are not supported.
@interface NSFileSecurity : NSObject <NSCopying>
{
@public
	uid_t _owner;
	gid_t _group;
	mode_t _mode;
	BOOL _hasOwner, _hasGroup, _hasMode;
}
@end

@implementation NSFileSecurity

- (id)copyWithZone:(NSZone *)zone
{
	NSFileSecurity *copy = [[NSFileSecurity allocWithZone:zone] init];
	copy->_owner = _owner;
	copy->_group = _group;
	copy->_mode = _mode;
	copy->_hasOwner = _hasOwner;
	copy->_hasGroup = _hasGroup;
	copy->_hasMode = _hasMode;
	return copy;
}

@end

#define SEC(ref) ((NSFileSecurity *)(id)(ref))

CFFileSecurityRef CFFileSecurityCreate(CFAllocatorRef allocator)
{
	return (CFFileSecurityRef)[[NSFileSecurity alloc] init];
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
	SEC(fileSec)->_mode = mode & 07777;
	SEC(fileSec)->_hasMode = YES;
	return true;
}

Boolean CFFileSecurityClearProperties(CFFileSecurityRef fileSec, CFOptionFlags clearPropertyMask)
{
	if (!fileSec) return false;
	if (clearPropertyMask & kCFFileSecurityClearOwner) SEC(fileSec)->_hasOwner = NO;
	if (clearPropertyMask & kCFFileSecurityClearGroup) SEC(fileSec)->_hasGroup = NO;
	if (clearPropertyMask & kCFFileSecurityClearMode) SEC(fileSec)->_hasMode = NO;
	return true;
}

// UUIDs and access control lists are not represented.
Boolean CFFileSecurityCopyOwnerUUID(CFFileSecurityRef fileSec, CFUUIDRef *ownerUUID) { return false; }
Boolean CFFileSecuritySetOwnerUUID(CFFileSecurityRef fileSec, CFUUIDRef ownerUUID) { return false; }
Boolean CFFileSecurityCopyGroupUUID(CFFileSecurityRef fileSec, CFUUIDRef *groupUUID) { return false; }
Boolean CFFileSecuritySetGroupUUID(CFFileSecurityRef fileSec, CFUUIDRef groupUUID) { return false; }
Boolean CFFileSecurityCopyAccessControlList(CFFileSecurityRef fileSec, acl_t *accessControlList) { return false; }
Boolean CFFileSecuritySetAccessControlList(CFFileSecurityRef fileSec, acl_t accessControlList) { return false; }
