//
//  NSURL.m
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#import <Foundation/NSURL.h>
#import <Foundation/NSException.h>
#import <Foundation/NSPathUtilities.h>
#import <CoreFoundation/CFString.h>
#import <CoreFoundation/CFURL.h>
#import <CoreFoundation/CFDictionary.h>
#import <CoreFoundation/CFPropertyList.h>
#import "CFInternal.h"
#import "CFPriv.h"
#import <CoreFoundation/CFURLPriv.h>
#import "NSURLInternal.h"
#import <CoreFoundation/CFFileSecurity.h>
#import <objc/runtime.h>
#include <sys/statvfs.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#define STACK_BUFFER_SIZE 100 // pretty safe bet this will be quite unlikely to use more than this since there are only 94 properties

// Defined here, not in Foundation: the macOS Foundation binary imports this key from CoreFoundation.
NSString *const NSThumbnail1024x1024SizeKey = @"NSThumbnail1024x1024SizeKey";
NSString *const NSURLAddedToDirectoryDateKey = @"NSURLAddedToDirectoryDateKey";
NSString *const NSURLKeysOfUnsetValuesKey = @"NSURLKeysOfUnsetValuesKey";
NSString *const NSURLNameKey = @"NSURLNameKey";
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLIsRegularFileKey = @"NSURLIsRegularFileKey";
NSString *const NSURLIsDirectoryKey = @"NSURLIsDirectoryKey";
NSString *const NSURLIsSymbolicLinkKey = @"NSURLIsSymbolicLinkKey";
NSString *const NSURLIsVolumeKey = @"NSURLIsVolumeKey";
NSString *const NSURLIsPackageKey = @"NSURLIsPackageKey";
NSString *const NSURLIsSystemImmutableKey = @"NSURLIsSystemImmutableKey";
NSString *const NSURLIsUserImmutableKey = @"NSURLIsUserImmutableKey";
NSString *const NSURLIsHiddenKey = @"NSURLIsHiddenKey";
NSString *const NSURLHasHiddenExtensionKey = @"NSURLHasHiddenExtensionKey";
NSString *const NSURLCreationDateKey = @"NSURLCreationDateKey";
NSString *const NSURLContentAccessDateKey = @"NSURLContentAccessDateKey";
NSString *const NSURLContentModificationDateKey = @"NSURLContentModificationDateKey";
NSString *const NSURLAttributeModificationDateKey = @"NSURLAttributeModificationDateKey";
NSString *const NSURLLinkCountKey = @"NSURLLinkCountKey";
NSString *const NSURLParentDirectoryURLKey = @"NSURLParentDirectoryURLKey";
NSString *const NSURLVolumeURLKey = @"NSURLVolumeURLKey";
NSString *const NSURLTypeIdentifierKey = @"NSURLTypeIdentifierKey";
NSString *const NSURLContentTypeKey = @"NSURLContentTypeKey";
NSString *const NSURLLocalizedTypeDescriptionKey = @"NSURLLocalizedTypeDescriptionKey";
NSString *const NSURLLabelNumberKey = @"NSURLLabelNumberKey";
NSString *const NSURLLabelColorKey = @"NSURLLabelColorKey";
NSString *const NSURLLocalizedLabelKey = @"NSURLLocalizedLabelKey";
NSString *const NSURLEffectiveIconKey = @"NSURLEffectiveIconKey";
NSString *const NSURLCustomIconKey = @"NSURLCustomIconKey";
NSString *const NSURLFileResourceIdentifierKey = @"NSURLFileResourceIdentifierKey";
NSString *const NSURLVolumeIdentifierKey = @"NSURLVolumeIdentifierKey";
NSString *const NSURLPreferredIOBlockSizeKey = @"NSURLPreferredIOBlockSizeKey";
NSString *const NSURLIsReadableKey = @"NSURLIsReadableKey";
NSString *const NSURLIsWritableKey = @"NSURLIsWritableKey";
NSString *const NSURLIsExecutableKey = @"NSURLIsExecutableKey";
NSString *const NSURLFileSecurityKey = @"NSURLFileSecurityKey";
NSString *const NSURLIsExcludedFromBackupKey = @"NSURLIsExcludedFromBackupKey";
NSString *const NSURLPathKey = @"_NSURLPathKey";
NSString *const NSURLIsMountTriggerKey = @"NSURLIsMountTriggerKey";
NSString *const NSURLFileResourceTypeKey = @"NSURLFileResourceTypeKey";
NSString *const NSURLFileResourceTypeNamedPipe = @"NSURLFileResourceTypeNamedPipe";
NSString *const NSURLFileResourceTypeCharacterSpecial = @"NSURLFileResourceTypeCharacterSpecial";
NSString *const NSURLFileResourceTypeDirectory = @"NSURLFileResourceTypeDirectory";
NSString *const NSURLFileResourceTypeBlockSpecial = @"NSURLFileResourceTypeBlockSpecial";
NSString *const NSURLFileResourceTypeRegular = @"NSURLFileResourceTypeRegular";
NSString *const NSURLFileResourceTypeSymbolicLink = @"NSURLFileResourceTypeSymbolicLink";
NSString *const NSURLFileResourceTypeSocket = @"NSURLFileResourceTypeSocket";
NSString *const NSURLFileResourceTypeUnknown = @"NSURLFileResourceTypeUnknown";
NSString *const NSURLFileSizeKey = @"NSURLFileSizeKey";
NSString *const NSURLFileAllocatedSizeKey = @"NSURLFileAllocatedSizeKey";
NSString *const NSURLTotalFileSizeKey = @"NSURLTotalFileSizeKey";
NSString *const NSURLTotalFileAllocatedSizeKey = @"NSURLTotalFileAllocatedSizeKey";
NSString *const NSURLIsAliasFileKey = @"NSURLIsAliasFileKey";
NSString *const NSURLVolumeLocalizedFormatDescriptionKey = @"NSURLVolumeLocalizedFormatDescriptionKey";
NSString *const NSURLVolumeTotalCapacityKey = @"NSURLVolumeTotalCapacityKey";
NSString *const NSURLVolumeAvailableCapacityKey = @"NSURLVolumeAvailableCapacityKey";
NSString *const NSURLVolumeResourceCountKey = @"NSURLVolumeResourceCountKey";
NSString *const NSURLVolumeSupportsPersistentIDsKey = @"NSURLVolumeSupportsPersistentIDsKey";
NSString *const NSURLVolumeSupportsSymbolicLinksKey = @"NSURLVolumeSupportsSymbolicLinksKey";
NSString *const NSURLVolumeSupportsHardLinksKey = @"NSURLVolumeSupportsHardLinksKey";
NSString *const NSURLVolumeSupportsJournalingKey = @"NSURLVolumeSupportsJournalingKey";
NSString *const NSURLVolumeIsJournalingKey = @"NSURLVolumeIsJournalingKey";
NSString *const NSURLVolumeSupportsSparseFilesKey = @"NSURLVolumeSupportsSparseFilesKey";
NSString *const NSURLVolumeSupportsZeroRunsKey = @"NSURLVolumeSupportsZeroRunsKey";
NSString *const NSURLVolumeSupportsCaseSensitiveNamesKey = @"NSURLVolumeSupportsCaseSensitiveNamesKey";
NSString *const NSURLVolumeSupportsCasePreservedNamesKey = @"NSURLVolumeSupportsCasePreservedNamesKey";
NSString *const NSURLVolumeSupportsRootDirectoryDatesKey = @"NSURLVolumeSupportsRootDirectoryDatesKey";
NSString *const NSURLVolumeSupportsVolumeSizesKey = @"NSURLVolumeSupportsVolumeSizesKey";
NSString *const NSURLVolumeSupportsRenamingKey = @"NSURLVolumeSupportsRenamingKey";
NSString *const NSURLVolumeSupportsAdvisoryFileLockingKey = @"NSURLVolumeSupportsAdvisoryFileLockingKey";
NSString *const NSURLVolumeSupportsExtendedSecurityKey = @"NSURLVolumeSupportsExtendedSecurityKey";
NSString *const NSURLVolumeSupportsCompressionKey = @"NSURLVolumeSupportsCompressionKey";
NSString *const NSURLVolumeSupportsFileCloningKey = @"NSURLVolumeSupportsFileCloningKey";
NSString *const NSURLVolumeSupportsSwapRenamingKey = @"NSURLVolumeSupportsSwapRenamingKey";
NSString *const NSURLVolumeSupportsExclusiveRenamingKey = @"NSURLVolumeSupportsExclusiveRenamingKey";
NSString *const NSURLVolumeSupportsImmutableFilesKey = @"NSURLVolumeSupportsImmutableFilesKey";
NSString *const NSURLVolumeSupportsAccessPermissionsKey = @"NSURLVolumeSupportsAccessPermissionsKey";
NSString *const NSURLVolumeSupportsFileProtectionKey = @"NSURLVolumeSupportsFileProtectionKey";
NSString *const NSURLVolumeIsBrowsableKey = @"NSURLVolumeIsBrowsableKey";
NSString *const NSURLVolumeMaximumFileSizeKey = @"NSURLVolumeMaximumFileSizeKey";
NSString *const NSURLVolumeIsEjectableKey = @"NSURLVolumeIsEjectableKey";
NSString *const NSURLVolumeIsRemovableKey = @"NSURLVolumeIsRemovableKey";
NSString *const NSURLVolumeIsInternalKey = @"NSURLVolumeIsInternalKey";
NSString *const NSURLVolumeIsAutomountedKey = @"NSURLVolumeIsAutomountedKey";
NSString *const NSURLVolumeIsLocalKey = @"NSURLVolumeIsLocalKey";
NSString *const NSURLVolumeIsReadOnlyKey = @"NSURLVolumeIsReadOnlyKey";
NSString *const NSURLVolumeCreationDateKey = @"NSURLVolumeCreationDateKey";
NSString *const NSURLVolumeURLForRemountingKey = @"NSURLVolumeURLForRemountingKey";
NSString *const NSURLVolumeUUIDStringKey = @"NSURLVolumeUUIDStringKey";
NSString *const NSURLVolumeNameKey = @"NSURLVolumeNameKey";
NSString *const NSURLVolumeLocalizedNameKey = @"NSURLVolumeLocalizedNameKey";
NSString *const NSURLIsUbiquitousItemKey = @"NSURLIsUbiquitousItemKey";
NSString *const NSURLUbiquitousItemHasUnresolvedConflictsKey = @"NSURLUbiquitousItemHasUnresolvedConflictsKey";
NSString *const NSURLUbiquitousItemIsDownloadedKey = @"NSURLUbiquitousItemIsDownloadedKey";
NSString *const NSURLUbiquitousItemIsDownloadingKey = @"NSURLUbiquitousItemIsDownloadingKey";
NSString *const NSURLUbiquitousItemIsUploadedKey = @"NSURLUbiquitousItemIsUploadedKey";
NSString *const NSURLUbiquitousItemIsUploadingKey = @"NSURLUbiquitousItemIsUploadingKey";
NSString *const NSURLUbiquitousItemPercentDownloadedKey = @"NSURLUbiquitousItemPercentDownloadedKey";
NSString *const NSURLUbiquitousItemPercentUploadedKey = @"NSURLUbiquitousItemPercentUploadedKey";
NSString *const NSURLTagNamesKey = @"NSURLTagNamesKey";
NSString *const NSURLUbiquitousItemDownloadingErrorKey = @"NSURLUbiquitousItemDownloadingErrorKey";
NSString *const NSURLUbiquitousItemDownloadingStatusKey = @"NSURLUbiquitousItemDownloadingStatusKey";
NSString *const NSURLApplicationIsScriptableKey = @"NSURLApplicationIsScriptableKey";
NSString *const NSURLCanonicalPathKey = @"NSURLCanonicalPathKey";
NSString *const NSURLDocumentIdentifierKey = @"NSURLDocumentIdentifierKey";
NSString *const NSURLGenerationIdentifierKey = @"NSURLGenerationIdentifierKey";
NSString *const NSURLIsApplicationKey = @"NSURLIsApplicationKey";
NSString *const NSURLQuarantinePropertiesKey = @"NSURLQuarantinePropertiesKey";
NSString *const NSURLUbiquitousItemContainerDisplayNameKey = @"NSURLUbiquitousItemContainerDisplayNameKey";
NSString *const NSURLUbiquitousItemDownloadRequestedKey = @"NSURLUbiquitousItemDownloadRequestedKey";
NSString *const NSURLUbiquitousItemIsSharedKey = @"NSURLUbiquitousItemIsSharedKey";
NSString *const NSURLUbiquitousItemUploadingErrorKey = @"NSURLUbiquitousItemUploadingErrorKey";
NSString *const NSURLUbiquitousSharedItemCurrentUserPermissionsKey = @"NSURLUbiquitousSharedItemCurrentUserPermissionsKey";
NSString *const NSURLUbiquitousSharedItemCurrentUserRoleKey = @"NSURLUbiquitousSharedItemCurrentUserRoleKey";
NSString *const NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey = @"NSURLUbiquitousSharedItemMostRecentEditorNameComponentsKey";
NSString *const NSURLUbiquitousSharedItemOwnerNameComponentsKey = @"NSURLUbiquitousSharedItemOwnerNameComponentsKey";
NSString *const NSURLVolumeAvailableCapacityForImportantUsageKey = @"NSURLVolumeAvailableCapacityForImportantUsageKey";
NSString *const NSURLVolumeAvailableCapacityForOpportunisticUsageKey = @"NSURLVolumeAvailableCapacityForOpportunisticUsageKey";
NSString *const NSURLVolumeIsEncryptedKey = @"NSURLVolumeIsEncryptedKey";
NSString *const NSURLVolumeIsRootFileSystemKey = @"NSURLVolumeIsRootFileSystemKey";
NSString *const NSURLIsPurgeableKey = @"NSURLIsPurgeableKey";
NSString *const NSURLIsSparseKey = @"NSURLIsSparseKey";
NSString *const NSURLMayHaveExtendedAttributesKey = @"NSURLMayHaveExtendedAttributesKey";
NSString *const NSURLMayShareFileContentKey = @"NSURLMayShareFileContentKey";
NSString *const NSURLDirectoryEntryCountKey = @"NSURLDirectoryEntryCountKey";
NSString *const NSURLFileIdentifierKey = @"NSURLFileIdentifierKey";
NSString *const NSURLFileContentIdentifierKey = @"NSURLFileContentIdentifierKey";
NSString *const NSURLFileProtectionKey = @"NSURLFileProtectionKey";
NSString *const NSURLThumbnailDictionaryKey = @"NSURLThumbnailDictionaryKey";
NSString *const NSURLThumbnailKey = @"NSURLThumbnailKey";
NSString *const NSURLVolumeTypeNameKey = @"NSURLVolumeTypeNameKey";
NSString *const NSURLVolumeSubtypeKey = @"NSURLVolumeSubtypeKey";
NSString *const NSURLVolumeMountFromLocationKey = @"NSURLVolumeMountFromLocationKey";
NSString *const NSURLUbiquitousItemIsExcludedFromSyncKey = @"NSURLUbiquitousItemIsExcludedFromSyncKey";
NSString *const NSURLUbiquitousItemIsSyncPausedKey = @"NSURLUbiquitousItemIsSyncPausedKey";
NSString *const NSURLUbiquitousItemSupportedSyncControlsKey = @"NSURLUbiquitousItemSupportedSyncControlsKey";

NSURLUbiquitousItemDownloadingStatus const NSURLUbiquitousItemDownloadingStatusNotDownloaded = @"NSURLUbiquitousItemDownloadingStatusNotDownloaded";
NSURLUbiquitousItemDownloadingStatus const NSURLUbiquitousItemDownloadingStatusDownloaded = @"NSURLUbiquitousItemDownloadingStatusDownloaded";
NSURLUbiquitousItemDownloadingStatus const NSURLUbiquitousItemDownloadingStatusCurrent = @"NSURLUbiquitousItemDownloadingStatusCurrent";
NSURLUbiquitousSharedItemRole const NSURLUbiquitousSharedItemRoleOwner = @"NSURLUbiquitousSharedItemRoleOwner";
NSURLUbiquitousSharedItemRole const NSURLUbiquitousSharedItemRoleParticipant = @"NSURLUbiquitousSharedItemRoleParticipant";
NSURLUbiquitousSharedItemPermissions const NSURLUbiquitousSharedItemPermissionsReadOnly = @"NSURLUbiquitousSharedItemPermissionsReadOnly";
NSURLUbiquitousSharedItemPermissions const NSURLUbiquitousSharedItemPermissionsReadWrite = @"NSURLUbiquitousSharedItemPermissionsReadWrite";

// Reports why an item cannot be reached the way the file reading errors of the Cocoa domain do:
// no such file, no permission, and any other failure as an unknown read error.
static void cocoaReadError(CFErrorRef *error, int posixCode)
{
    if (error == NULL)
    {
        return;
    }

    CFIndex code = 256; // NSFileReadUnknownError
    if (posixCode == ENOENT || posixCode == ENOTDIR)
    {
        code = 260; // NSFileReadNoSuchFileError
    }
    else if (posixCode == EACCES || posixCode == EPERM)
    {
        code = 257; // NSFileReadNoPermissionError
    }

    CFErrorRef underlying = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, posixCode, NULL);
    const CFStringRef keys[1] = { kCFErrorUnderlyingErrorKey };
    CFTypeRef values[1] = { underlying };
    *error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainCocoa, code, (const void *const *)keys, (const void *const *)values, 1);
    CFRelease(underlying);
}

// A failed read of an item's resource values is reported as the Cocoa file-reading error
// (NSFileReadNoSuchFileError for a missing item) with the POSIX error underneath.
static void resourceReadError(CFErrorRef *error) {
    cocoaReadError(error, errno);
}

// kCFErrorUnderlyingErrorKey values must be CFErrors: CFError's description reads them as such.
static void posixError(CFErrorRef *error) {
    int saved_errno = errno;
    const CFStringRef keys[1] = {
        kCFErrorUnderlyingErrorKey,
    };
    CFErrorRef underlyingError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, saved_errno, NULL);
    CFTypeRef values[1] = {
        underlyingError,
    };

    if (error != NULL)
    {
        *error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainPOSIX, saved_errno, (const void *const *)keys, (const void *const *)values, 1);
    }

    CFRelease(underlyingError);
}

static void dlError(CFErrorRef *error) {
    int saved_errno = errno;
    const CFStringRef descriptionKey = kCFErrorLocalizedDescriptionKey;
    CFStringRef description = CFStringCreateWithCString(kCFAllocatorDefault, dlerror(), kCFStringEncodingUTF8);
    CFTypeRef descriptionValue = description;
    CFErrorRef underlyingError = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainPOSIX, saved_errno, (const void *const *) &descriptionKey, (const void *const *) &descriptionValue, 1);
    const CFStringRef key = kCFErrorUnderlyingErrorKey;
    CFTypeRef value = underlyingError;

    if(error != NULL)
        *error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainPOSIX, saved_errno, (const void *const *) &key, (const void *const *) &value, 1);
    CFRelease(underlyingError);
    CFRelease(description);
};

static Boolean CFURLStat(CFURLRef url, struct stat *info) {
    UInt8 path[PATH_MAX] = { 0 };

    if (CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
    {
        // Resource metadata describes the link itself, including a dangling link.
        return lstat(path, info) != -1;
    }

    return false;
}

// Whether the item is the root directory of a volume (NSURLIsVolumeKey): a directory whose parent is on
// another device, or is the directory itself (the root of the file system). A bind mount within one device
// is not told apart from an ordinary directory. Returns false with errno set when that cannot be told:
// the item is missing, or it is a directory the process may not search (its parent is reached through it).
static Boolean CFURLGetIsVolumeRoot(CFURLRef url, Boolean *isRoot)
{
    UInt8 path[PATH_MAX + 4] = { 0 };
    struct stat item, parent;

    if (!CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
    {
        errno = EINVAL;
        return false;
    }
    if (lstat((const char *)path, &item) == -1)
    {
        return false;
    }
    if (!S_ISDIR(item.st_mode))
    {
        *isRoot = false;
        return true;
    }

    strlcat((char *)path, "/..", sizeof(path));
    if (stat((const char *)path, &parent) == -1)
    {
        return false;
    }
    *isRoot = item.st_dev != parent.st_dev || item.st_ino == parent.st_ino;
    return true;
}

// The uniform type identifier comes from LaunchServices (as on macOS), which CoreFoundation loads at
// run time. NSURLContentTypeKey needs a UTType object, which belongs to UniformTypeIdentifiers, a
// framework above Foundation; CoreFoundation does not reach up to it and leaves that key unhandled.
static void *UTLaunchServicesHandle;
static CFErrorRef UTLoadError;
static CFStringRef (*UTCreatePreferredIdentifierForTag)(CFStringRef, CFStringRef, CFStringRef);
static Boolean (*UTConformsTo)(CFStringRef, CFStringRef);
static CFStringRef *UTTagClassFilenameExtension;

static void CFURLLoadLaunchServices(void *context)
{
    UTLaunchServicesHandle = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_LOCAL);
    if (UTLaunchServicesHandle == NULL)
    {
        dlError(&UTLoadError);
        return;
    }
    UTCreatePreferredIdentifierForTag = dlsym(UTLaunchServicesHandle, "UTTypeCreatePreferredIdentifierForTag");
    UTConformsTo = dlsym(UTLaunchServicesHandle, "UTTypeConformsTo");
    UTTagClassFilenameExtension = dlsym(UTLaunchServicesHandle, "kUTTagClassFilenameExtension");
    if (UTCreatePreferredIdentifierForTag == NULL || UTConformsTo == NULL || UTTagClassFilenameExtension == NULL)
        dlError(&UTLoadError);
}

static void CFURLEnsureLaunchServices(void)
{
    static dispatch_once_t once;
    dispatch_once_f(&once, NULL, CFURLLoadLaunchServices);
}

// Links, folders, directory types that are declared (.app) and files; a path with no extension
// is public.data (public.unix-executable when executable).
static CFStringRef CFURLCreateTypeIdentifier(CFURLRef url, CFErrorRef *error)
{
    CFURLEnsureLaunchServices();
    if (UTCreatePreferredIdentifierForTag == NULL || UTConformsTo == NULL || UTTagClassFilenameExtension == NULL)
    {
        if (error != NULL && UTLoadError != NULL)
            *error = (CFErrorRef)CFRetain(UTLoadError);
        return NULL;
    }

    struct stat info;
    if (!CFURLStat(url, &info))
    {
        resourceReadError(error);
        return NULL;
    }

    if (S_ISLNK(info.st_mode))
        return CFRetain(CFSTR("public.symlink"));

    CFStringRef extension = CFURLCopyPathExtension(url);
    Boolean hasExtension = extension != NULL && CFStringGetLength(extension) > 0;
    CFStringRef result = NULL;

    if (S_ISDIR(info.st_mode))
    {
        if (hasExtension)
        {
            CFStringRef candidate = UTCreatePreferredIdentifierForTag(*UTTagClassFilenameExtension, extension, CFSTR("public.directory"));
            // An extension that no type declares comes back as a dynamic identifier: a plain folder.
            if (candidate != NULL && !CFStringHasPrefix(candidate, CFSTR("dyn.")) && UTConformsTo(candidate, CFSTR("public.directory")))
                result = candidate;
            else if (candidate != NULL)
                CFRelease(candidate);
        }
        if (result == NULL)
            result = CFRetain(CFSTR("public.folder"));
    }
    else if (hasExtension)
    {
        result = UTCreatePreferredIdentifierForTag(*UTTagClassFilenameExtension, extension, CFSTR("public.data"));
    }
    else
    {
        result = CFRetain((info.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) ? CFSTR("public.unix-executable") : CFSTR("public.data"));
    }

    if (extension != NULL)
        CFRelease(extension); // CFURLCopyPathExtension returns NULL for paths without an extension
    return result;
}

// NSURLContentTypeKey: the UTType object for the item's uniform type identifier. UTType belongs to
// UniformTypeIdentifiers, a framework above Foundation, so it is reached through the Objective-C
// runtime once an identifier exists; a process without the framework reads the key as nil.
static CFTypeRef CFURLCreateContentType(CFURLRef url, CFErrorRef *error)
{
    CFStringRef identifier = CFURLCreateTypeIdentifier(url, error);
    if (identifier == NULL)
        return NULL;

    static dispatch_once_t once;
    static Class typeClass;
    dispatch_once(&once, ^{
        typeClass = objc_getClass("UTType");
        if (typeClass == Nil)
        {
            dlopen("/System/Library/Frameworks/UniformTypeIdentifiers.framework/UniformTypeIdentifiers", RTLD_LAZY | RTLD_LOCAL);
            typeClass = objc_getClass("UTType");
        }
    });

    CFTypeRef result = NULL;
    if (typeClass != Nil)
    {
        id type = [typeClass typeWithIdentifier:(NSString *)identifier];
        if (type != nil)
            result = CFRetain(type);
    }
    CFRelease(identifier);
    return result;
}

// The Finder flags live in bytes 8 and 9 (big endian) of the 32-byte "com.apple.FinderInfo"
// extended attribute; kExtensionIsHidden is the 0x0010 bit of that word and kHasBundle the 0x2000 bit.
enum {
    kFinderInfoSize = 32,
    kFinderFlagsOffset = 8,
    kFinderExtensionIsHidden = 0x0010,
    kFinderHasBundle = 0x2000,
};

// Reads the FinderInfo of the item itself (a symbolic link is not followed). Returns false
// with errno set when the item cannot be accessed; an item without FinderInfo, or on a file
// system that cannot hold extended attributes, reads as all zeros.
static Boolean CFURLReadFinderInfo(CFURLRef url, UInt8 *info)
{
    UInt8 path[PATH_MAX] = { 0 };

    memset(info, 0, kFinderInfoSize);
    if (!CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
    {
        errno = EINVAL;
        return false;
    }

    ssize_t length = getxattr((const char *)path, XATTR_FINDERINFO_NAME, info, kFinderInfoSize, 0, XATTR_NOFOLLOW);
    if (length < 0)
    {
        if (errno == ENOATTR || errno == ENOTSUP || errno == EPERM)
        {
            return true;
        }
        return false;
    }
    return true;
}

static Boolean CFURLCopyExtensionIsHidden(CFURLRef url, Boolean *hidden)
{
    UInt8 info[kFinderInfoSize];

    if (!CFURLReadFinderInfo(url, info))
    {
        return false;
    }
    *hidden = (((info[kFinderFlagsOffset] << 8) | info[kFinderFlagsOffset + 1]) & kFinderExtensionIsHidden) != 0;
    return true;
}

// The provider LaunchServices registers to answer kCFURLIsPackageKey from its type registry.
static _CFURLPackageProvider CFURLPackageProvider;

void _CFURLSetPackageProvider(_CFURLPackageProvider provider)
{
    __atomic_store_n(&CFURLPackageProvider, provider, __ATOMIC_RELEASE);
}

// Whether an existing directory is a package. The Finder's bundle bit makes any directory one.
// Everything else depends on the directory's type (an extension declared as conforming to
// com.apple.package, or a document type declared as a package), which only LaunchServices knows.
// As on macOS, where a program that links only CoreFoundation gets LaunchServices loaded on its
// first package question, LaunchServices is loaded here if nothing has registered yet; it
// registers its provider when it loads. Without it, only the bundle bit counts.
static Boolean CFURLDirectoryIsPackage(CFURLRef url)
{
    UInt8 info[kFinderInfoSize];

    if (CFURLReadFinderInfo(url, info) && (((info[kFinderFlagsOffset] << 8) | info[kFinderFlagsOffset + 1]) & kFinderHasBundle) != 0)
    {
        return true;
    }

    _CFURLPackageProvider provider = __atomic_load_n(&CFURLPackageProvider, __ATOMIC_ACQUIRE);
    if (provider == NULL)
    {
        CFURLEnsureLaunchServices();
        provider = __atomic_load_n(&CFURLPackageProvider, __ATOMIC_ACQUIRE);
    }
    return provider != NULL && provider(url);
}

// Sets or clears the extension-hidden flag, leaving the rest of the FinderInfo as it is.
static Boolean CFURLSetExtensionIsHidden(CFURLRef url, Boolean hidden)
{
    UInt8 info[kFinderInfoSize];
    UInt8 path[PATH_MAX] = { 0 };

    if (!CFURLReadFinderInfo(url, info))
    {
        return false;
    }

    UInt16 flags = (info[kFinderFlagsOffset] << 8) | info[kFinderFlagsOffset + 1];
    UInt16 updated = hidden ? (flags | kFinderExtensionIsHidden) : (flags & ~kFinderExtensionIsHidden);
    if (updated == flags && (hidden == false))
    {
        // Nothing to clear, and no attribute needs to be created for that.
        return true;
    }

    info[kFinderFlagsOffset] = updated >> 8;
    info[kFinderFlagsOffset + 1] = updated & 0xFF;

    CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX);
    return setxattr((const char *)path, XATTR_FINDERINFO_NAME, info, kFinderInfoSize, 0, XATTR_NOFOLLOW) == 0;
}

static pthread_mutex_t resInfoLock = PTHREAD_MUTEX_INITIALIZER;

static CFTypeRef CFURLCreatePropertyForKey(CFURLRef url, CFStringRef key, CFErrorRef *error)
{
    CFTypeRef value = NULL;
    struct stat info;
    // NOTE: not all of the properties are currently supported, however the most common ones should have quasi-reasonable implementations
    if (CFEqual(key, kCFURLNameKey))
    {
        // Key for the resource's name in the file system, returned as a CFString object. It is the last
        // path component as it is, extension included, and an item that is not there is a read error.
        if (CFURLStat(url, &info))
        {
            value = CFURLCopyLastPathComponent(url);
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLLocalizedNameKey))
    {
        // Key for the resource's localized or extension-hidden name, returned as a CFString object: the file
        // name, without its extension when the item has the extension-hidden flag set.
        if (CFURLStat(url, &info))
        {
            Boolean hidden = false;
            if (CFURLCopyExtensionIsHidden(url, &hidden) && hidden)
            {
                CFURLRef trimmed = CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, url);
                value = CFURLCopyLastPathComponent(trimmed);
                CFRelease(trimmed);
            }
            else
            {
                value = CFURLCopyLastPathComponent(url);
            }
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLPathKey))
    {
        // A CFString value containing the URL’s path as a file system path. (read-only)
        value = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
    }
    else if (CFEqual(key, kCFURLIsRegularFileKey))
    {
        // Key for determining whether the resource is a regular file, as opposed to a directory or a symbolic link. Returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = S_ISREG(info.st_mode) ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsDirectoryKey))
    {
        // Key for determining whether the resource is a directory, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = S_ISDIR(info.st_mode) ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsSymbolicLinkKey))
    {
        // Key for determining whether the resource is a directory, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = S_ISLNK(info.st_mode) ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsVolumeKey))
    {
        Boolean isRoot = false;

        if (CFURLGetIsVolumeRoot(url, &isRoot))
        {
            value = isRoot ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsPackageKey))
    {
        // Key for whether the resource is a package: a directory (a symbolic link is not one)
        // that is presented as a single file. Returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (S_ISDIR(info.st_mode) && CFURLDirectoryIsPackage(url)) ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsSystemImmutableKey))
    {
        // Key for determining whether the resource's system immutable bit is set, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (info.st_mode & S_IWOTH) != S_IWOTH ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsUserImmutableKey))
    {
        // Key for determining whether the resource's user immutable bit is set, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (info.st_mode & S_IWUSR) != S_IWUSR ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsHiddenKey))
    {
        CFStringRef lastPathComp = CFURLCopyLastPathComponent(url);
        Boolean isHidden = false;

        if (CFStringGetLength(lastPathComp) > 0)
        {
            isHidden = CFStringGetCharacterAtIndex(lastPathComp, 0) == '.';
        }

        value = isHidden ? kCFBooleanTrue : kCFBooleanFalse;
        CFRelease(lastPathComp);
    }
    else if (CFEqual(key, kCFURLHasHiddenExtensionKey))
    {
        // Key for whether the Finder hides the file name extension, returned as a CFBoolean
        // object from the extension-hidden bit of the item's FinderInfo.
        Boolean hidden = false;

        if (CFURLCopyExtensionIsHidden(url, &hidden))
        {
            value = hidden ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLCreationDateKey))
    {
        // Key for the resource’s creation date, returned as a CFDate object if the volume supports creation dates, or nil if creation dates are unsupported.
        if (CFURLStat(url, &info))
        {
            value = CFDateCreate(kCFAllocatorDefault, _CFAbsoluteTimeFromFileTimeSpec(info.st_ctimespec));
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLContentAccessDateKey))
    {
        if (CFURLStat(url, &info))
        {
            value = CFDateCreate(kCFAllocatorDefault, _CFAbsoluteTimeFromFileTimeSpec(info.st_atimespec));
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLContentModificationDateKey))
    {
        if (CFURLStat(url, &info))
        {
            value = CFDateCreate(kCFAllocatorDefault, _CFAbsoluteTimeFromFileTimeSpec(info.st_mtimespec));
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLAttributeModificationDateKey))
    {
        if (CFURLStat(url, &info))
        {
            value = CFDateCreate(kCFAllocatorDefault, _CFAbsoluteTimeFromFileTimeSpec(info.st_mtimespec));
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLLinkCountKey))
    {
        // Key for the number of hard links to the resource, returned as a CFNumber object.
        if (CFURLStat(url, &info))
        {
            value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &info.st_nlink);
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLParentDirectoryURLKey))
    {
        // Key for the parent directory of the resource, returned as a CFURL object, or nil if the resource is the root directory of its volume.
        Boolean isRoot = false;

        // A missing item is the same file read error as for the other keys (macOS 26.7.3 gives error 260 for it,
        // tier 2 observation; test: tests/nsurl-volume-and-identifier-keys.m). When the root question cannot be
        // answered for another reason (a directory that may not be searched) the parent is the URL's parent.
        if (!CFURLGetIsVolumeRoot(url, &isRoot))
        {
            if (errno == ENOENT || errno == ENOTDIR)
            {
                resourceReadError(error);
            }
            else
            {
                value = CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, url);
            }
        }
        else if (!isRoot)
        {
            value = CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, url);
        }
    }
    else if (CFEqual(key, kCFURLVolumeURLKey))
    {
        // is this doable?
    }
    else if (CFEqual(key, kCFURLTypeIdentifierKey))
    {
        // Key for the resource’s uniform type identifier (UTI), returned as a CFString object.
        value = CFURLCreateTypeIdentifier(url, error);
    }
    else if (CFEqual(key, CFSTR("NSURLContentTypeKey")))
    {
        value = CFURLCreateContentType(url, error);
    }
    else if (CFEqual(key, kCFURLLocalizedTypeDescriptionKey))
    {
        // Key for the resource’s localized type description, returned as a CFString object.

    }
    else if (CFEqual(key, kCFURLLabelNumberKey))
    {
        // Key for the resource’s label number, returned as a CFNumber object.
    }
    else if (CFEqual(key, kCFURLLabelColorKey))
    {
        
    }
    else if (CFEqual(key, kCFURLLocalizedLabelKey))
    {
        
    }
    else if (CFEqual(key, kCFURLEffectiveIconKey))
    {
        
    }
    else if (CFEqual(key, kCFURLCustomIconKey))
    {
        
    }
    else if (CFEqual(key, kCFURLFileResourceIdentifierKey))
    {
        // Key for the resource’s unique identifier, returned as a CFType object.
        // This identifier can be used to determine equality between file system resources with the CFEqual function. Two resources are equal if they have the same file-system path or if their paths link to the same inode on the same file system.
        // The value of this identifier is not persistent across system restarts.
        // Available in iOS 5.0 and later.
        // The value is the device and inode numbers as CFData: equal data for paths to the same inode of one file system.
        if (CFURLStat(url, &info))
        {
            UInt64 identity[2] = { (UInt64)info.st_dev, (UInt64)info.st_ino };
            value = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)identity, sizeof(identity));
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLVolumeIdentifierKey))
    {
        
    }
    else if (CFEqual(key, kCFURLFileSizeKey))
    {
        if (CFURLStat(url, &info))
        {
            int64_t size = info.st_size;
            value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &size);
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLPreferredIOBlockSizeKey))
    {
        // Key for the optimal block size to use when reading or writing this file's data, returned as a CFNumber object, or NULL if the preferred size is not available.
        if (CFURLStat(url, &info))
        {
            value = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &info.st_blksize);
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsReadableKey))
    {
        // Key for determining whether the current process (as determined by the EUID) can read the resource, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (info.st_mode & S_IRUSR) == S_IRUSR ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsWritableKey))
    {
        // Key for determining whether the current process (as determined by the EUID) can write to the resource, returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (info.st_mode & S_IWUSR) == S_IWUSR ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsExecutableKey))
    {
        // Key for determining whether the current process (as determined by the EUID) can execute the resource (if it is a file) or search the resource (if it is a directory), returned as a CFBoolean object.
        if (CFURLStat(url, &info))
        {
            value = (info.st_mode & S_IXUSR) == S_IXUSR ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLFileSecurityKey))
    {
        // Owner, group and permission bits; ACLs and UUIDs are not represented.
        if (CFURLStat(url, &info))
        {
            CFFileSecurityRef security = CFFileSecurityCreate(kCFAllocatorDefault);
            CFFileSecuritySetOwner(security, info.st_uid);
            CFFileSecuritySetGroup(security, info.st_gid);
            CFFileSecuritySetMode(security, info.st_mode & 07777);
            value = security;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLIsExcludedFromBackupKey))
    {
        // CFBoolean statics are immortal (CFRuntime.h:231-233), so no CFRetain: CFRelease returns at once (CFRuntime.c:1438).
        value = kCFBooleanTrue;
    }
    else if (CFEqual(key, kCFURLFileResourceTypeKey))
    {
        // Key for the resource’s object type, returned as a CFString object. See “File Resource Types” for possible values.
    }
    else if (CFEqual(key, kCFURLVolumeIsReadOnlyKey))
    {
        // The volume of the item a symbolic link points to, like the capacity keys below (statvfs follows links).
        UInt8 path[PATH_MAX] = { 0 };
        struct statvfs vfs;

        if (!CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
        {
            errno = EINVAL;
            resourceReadError(error);
        }
        else if (statvfs((const char *)path, &vfs) == 0)
        {
            value = (vfs.f_flag & ST_RDONLY) ? kCFBooleanTrue : kCFBooleanFalse;
        }
        else
        {
            resourceReadError(error);
        }
    }
    else if (CFEqual(key, kCFURLVolumeAvailableCapacityKey))
    {
        UInt8 path[PATH_MAX] = { 0 };

        if (CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
        {
            struct statvfs vfs;
            if (statvfs(path, &vfs) == 0)
            {
                long long b = ((UInt64)vfs.f_bavail) * vfs.f_bsize;
                value = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &b);
            }
        }
    }
    else if (CFEqual(key, kCFURLVolumeAvailableCapacityForImportantUsageKey))
    {
        UInt8 path[PATH_MAX] = { 0 };

        if (CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
        {
            struct statvfs vfs;
            if (statvfs(path, &vfs) == 0)
            {
                long long b = ((UInt64)vfs.f_bfree) * vfs.f_bsize;
                value = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &b);
            }
        }
    }
    else if (CFEqual(key, kCFURLVolumeSupportsFileCloningKey) ||
             CFEqual(key, kCFURLVolumeSupportsSwapRenamingKey) ||
             CFEqual(key, kCFURLVolumeSupportsExclusiveRenamingKey) ||
             CFEqual(key, kCFURLVolumeSupportsImmutableFilesKey) ||
             CFEqual(key, kCFURLVolumeSupportsAccessPermissionsKey) ||
             CFEqual(key, kCFURLVolumeSupportsFileProtectionKey) ||
             CFEqual(key, kCFURLVolumeSupportsCompressionKey))
    {
        // These capabilities are not probed per file system yet: every volume is
        // reported as lacking them. That is the conservative answer (callers fall
        // back to the generic code path) and has not been checked against macOS
        // for any particular file system.
        // CFBoolean statics are immortal (CFRuntime.h:231-233), so no CFRetain: CFRelease returns at once (CFRuntime.c:1438).
        value = kCFBooleanFalse;
    }
    else if (CFEqual(key, kCFURLVolumeTotalCapacityKey))
    {
        UInt8 path[PATH_MAX] = { 0 };

        if (CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
        {
            struct statvfs vfs;
            if (statvfs(path, &vfs) == 0)
            {
                long long b = ((UInt64)vfs.f_blocks) * vfs.f_bsize;
                value = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongLongType, &b);
            }
        }
    }

    return value;
}

static const void *nullSafeRetain(CFAllocatorRef allocator, const void *value)
{
    if (value != NULL)
    {
        return (const void *)CFRetain((CFTypeRef)value);
    }
    else
    {
        return NULL;
    }
}

static void nullSafeRelease(CFAllocatorRef allocator, const void *value)
{
    if (value != NULL)
    {
        CFRelease((CFTypeRef)value);
    }
}

static CFStringRef nullSafeCopyDescription(const void *value)
{
    if (value != NULL)
    {
        return CFCopyDescription((CFTypeRef)value);
    }
    else
    {
        return CFSTR("(null)");
    }
}

static Boolean nullSafeEqual(const void *value1, const void *value2)
{
    if (value1 == NULL || value2 == NULL)
    {
        return value1 == value2;
    }
    else
    {
        return CFEqual((CFTypeRef)value1, (CFTypeRef)value2);
    }
}


static CFDictionaryValueCallBacks nullSafeCallbacks = {
    0,
    &nullSafeRetain,
    &nullSafeRelease,
    &nullSafeCopyDescription,
    &nullSafeEqual,
};

static inline CFMutableDictionaryRef CFURLResourceInfo(CFURLRef url)
{
    CFMutableDictionaryRef resourceInfo = __CFURLResourceInfoPtr(url);
    pthread_mutex_lock(&resInfoLock);

    if (resourceInfo == NULL)
    {
        resourceInfo = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFCopyStringDictionaryKeyCallBacks, &nullSafeCallbacks);
        __CFURLSetResourceInfoPtr(url, resourceInfo); // retains the info
        CFRelease(resourceInfo);
    }

    resourceInfo = (CFMutableDictionaryRef)CFRetain(resourceInfo);
    pthread_mutex_unlock(&resInfoLock);
    return resourceInfo;
}

static inline void CFURLResourceInfoUpdate(CFMutableDictionaryRef info, CFStringRef key, CFTypeRef value)
{
    pthread_mutex_lock(&resInfoLock);
    CFDictionarySetValue(info, key, value);
    pthread_mutex_unlock(&resInfoLock);
}

static inline void CFURLResourceInfoUpdateRelease(CFMutableDictionaryRef info, CFStringRef key, CFTypeRef value)
{
    pthread_mutex_lock(&resInfoLock);
    CFDictionarySetValue(info, key, value);
    CFRelease(info);
    pthread_mutex_unlock(&resInfoLock);
}

static inline void CFURLResourceInfoRelease(CFMutableDictionaryRef info)
{
    pthread_mutex_lock(&resInfoLock);
    CFRelease(info);
    pthread_mutex_unlock(&resInfoLock);
}

// Temporary resource values belong to the URL object and are consulted only for keys that the
// system does not provide, so they never shadow a computed value. They live in a nested
// dictionary of the resource cache so that clearing the cache clears them too.
static const CFStringRef CFURLTemporaryValuesKey = CFSTR("_NSURLTemporaryResourceValues");

static CFTypeRef CFURLCopyTemporaryValue(CFMutableDictionaryRef info, CFStringRef key)
{
    CFTypeRef value = NULL;

    pthread_mutex_lock(&resInfoLock);
    CFMutableDictionaryRef temporary = (CFMutableDictionaryRef)CFDictionaryGetValue(info, CFURLTemporaryValuesKey);
    if (temporary != NULL)
    {
        value = CFDictionaryGetValue(temporary, key);
        if (value != NULL)
        {
            CFRetain(value);
        }
    }
    pthread_mutex_unlock(&resInfoLock);
    return value;
}

// QUIRK: temporary resource values are kept only for file URLs; reading a key set on another
// kind of URL reports success with no value. Not documented. Evidence: black-box observation
// on Mac OS X 10.14.4 and macOS 26.7.3 (tier 2), vd-upstream MC-NSURL-V430A.
// Test: nsurl-temporary-resource-values (non-file URL case).
static void CFURLSetTemporaryResourceValue(CFURLRef url, CFStringRef key, CFTypeRef value)
{
    // Observed on the same systems: a nil value leaves an earlier value in place.
    if (value == NULL || !_CFURLIsFileURL(url))
    {
        return;
    }

    CFMutableDictionaryRef info = CFURLResourceInfo(url);

    pthread_mutex_lock(&resInfoLock);
    CFMutableDictionaryRef temporary = (CFMutableDictionaryRef)CFDictionaryGetValue(info, CFURLTemporaryValuesKey);
    if (temporary == NULL)
    {
        temporary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(info, CFURLTemporaryValuesKey, temporary);
        CFRelease(temporary);
    }
    CFDictionarySetValue(temporary, key, value);
    CFRelease(info);
    pthread_mutex_unlock(&resInfoLock);
}

static void CFURLRemoveCachedResourceValue(CFURLRef url, CFStringRef key)
{
    CFMutableDictionaryRef info = CFURLResourceInfo(url);

    pthread_mutex_lock(&resInfoLock);
    CFDictionaryRemoveValue(info, key);
    CFMutableDictionaryRef temporary = (CFMutableDictionaryRef)CFDictionaryGetValue(info, CFURLTemporaryValuesKey);
    if (temporary != NULL)
    {
        CFDictionaryRemoveValue(temporary, key);
    }
    CFRelease(info);
    pthread_mutex_unlock(&resInfoLock);
}

static void CFURLRemoveAllCachedResourceValues(CFURLRef url)
{
    CFMutableDictionaryRef info = CFURLResourceInfo(url);

    pthread_mutex_lock(&resInfoLock);
    CFDictionaryRemoveAllValues(info);
    CFRelease(info);
    pthread_mutex_unlock(&resInfoLock);
}

Boolean CFURLCopyResourcePropertyForKey(CFURLRef url, CFStringRef key, void *propertyValueTypeRefPtr, CFErrorRef *error)
{
    if (propertyValueTypeRefPtr != NULL)
    {
        *(CFTypeRef *)propertyValueTypeRefPtr = NULL;
    }

    if (error != NULL)
    {
        *error = NULL;
    }

    CFMutableDictionaryRef resourceInfo = CFURLResourceInfo(url);
    CFTypeRef value = (CFTypeRef)CFDictionaryGetValue(resourceInfo, key);
    Boolean fromTemporary = false;
    Boolean failed = false;

    if (value == NULL)
    {
        CFErrorRef propertyError = NULL;
        value = CFURLCreatePropertyForKey(url, key, &propertyError);
        if (value == NULL && propertyError == NULL)
        {
            value = CFURLCopyTemporaryValue(resourceInfo, key);
            fromTemporary = value != NULL;
        }
        if (value == NULL && propertyError != NULL)
        {
            failed = true;
            if (error != NULL)
            {
                *error = propertyError;
            }
            else
            {
                CFRelease(propertyError);
            }
        }
    }
    else
    {
        value = CFRetain(value);
    }

    if (propertyValueTypeRefPtr != NULL)
    {
        *(CFTypeRef *)propertyValueTypeRefPtr = value;
    }

    if (fromTemporary)
    {
        CFURLResourceInfoRelease(resourceInfo);
    }
    else
    {
        CFURLResourceInfoUpdateRelease(resourceInfo, key, value);
    }

    // With an out pointer, the reference held here goes to the caller (the Copy rule).
    if (value != NULL && propertyValueTypeRefPtr == NULL)
    {
        CFRelease(value);
    }

    // A key that has no value and no error (not set, or not applicable to the item) is a
    // successful read of nil, as the documentation of getResourceValue:forKey:error: describes.
    return !failed;
}

CFDictionaryRef CFURLCopyResourcePropertiesForKeys(CFURLRef url, CFArrayRef keys, CFErrorRef *error)
{
    CFDictionaryRef props = NULL;
    CFTypeRef stack_keys[STACK_BUFFER_SIZE] = { NULL };
    CFTypeRef stack_values[STACK_BUFFER_SIZE] = { NULL };
    CFTypeRef *property_keys = &stack_keys[0];
    CFTypeRef *property_values = &stack_values[0];
    CFMutableDictionaryRef resourceInfo = CFURLResourceInfo(url);
    CFIndex count = CFArrayGetCount(keys);
    CFIndex propCount = 0;
    Boolean failed = false;
    if (count > STACK_BUFFER_SIZE)
    {
        property_keys = malloc(sizeof(CFTypeRef) * count);

        if (property_keys == NULL)
        {
            // populate malloc error here
            return NULL;
        }

        property_values = malloc(sizeof(CFTypeRef) * count);

        if (property_values == NULL)
        {
            free(property_keys);
            // populate malloc error here
            return NULL;
        }
    }

    for (CFIndex idx = 0; idx < count; idx++)
    {
        CFStringRef key = CFArrayGetValueAtIndex(keys, idx);
        CFTypeRef value = (CFTypeRef)CFDictionaryGetValue(resourceInfo, key);
        Boolean fromTemporary = false;

        if (value == NULL)
        {
            CFErrorRef propertyError = NULL;
            value = CFURLCreatePropertyForKey(url, key, &propertyError);
            if (value == NULL && propertyError == NULL)
            {
                value = CFURLCopyTemporaryValue(resourceInfo, key);
                fromTemporary = value != NULL;
            }
            if (value == NULL && propertyError != NULL)
            {
                // Like macOS, fail the whole request (e.g. a missing file) instead of leaving the key out.
                if (error != NULL)
                {
                    *error = propertyError;
                }
                else
                {
                    CFRelease(propertyError);
                }
                failed = true;
                break;
            }
        }
        else
        {
            value = CFRetain(value);
        }

        if (!fromTemporary)
        {
            CFURLResourceInfoUpdate(resourceInfo, key, value);
        }

        if (value != NULL)
        {
            property_keys[propCount] = key;
            property_values[propCount] = value;
            propCount++;
        }

    }

    CFURLResourceInfoRelease(resourceInfo);

    if (!failed)
    {
        props = CFDictionaryCreate(kCFAllocatorDefault, property_keys, property_values, propCount, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }

    if (property_keys != &stack_keys[0])
    {
        free(property_keys);
    }

    for (CFIndex idx = 0; idx < propCount; idx++)
    {
        CFRelease(property_values[idx]);
    }

    if (property_values != &stack_values[0])
    {
        free(property_values);
    }

    return props;
}

static CFTypeRef CFURLSetPropertyForKey(CFURLRef url, CFStringRef key, CFTypeRef value, CFErrorRef *error) {
    CFTypeRef acceptedValue = NULL;
    // Verify that these only set meta-data and not twiddle real file system items
    if (CFEqual(key, kCFURLNameKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLLocalizedNameKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLPathKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsRegularFileKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsDirectoryKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsSymbolicLinkKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsVolumeKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsPackageKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsSystemImmutableKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsUserImmutableKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsHiddenKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLHasHiddenExtensionKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        if (CFURLSetExtensionIsHidden(url, CFBooleanGetValue(value)))
        {
            acceptedValue = CFRetain(value);
        }
        else
        {
            posixError(error);
        }
    }
    else if (CFEqual(key, kCFURLCreationDateKey) && CFGetTypeID(value) == CFDateGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLContentAccessDateKey) && CFGetTypeID(value) == CFDateGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLContentModificationDateKey) && CFGetTypeID(value) == CFDateGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLAttributeModificationDateKey) && CFGetTypeID(value) == CFDateGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLLinkCountKey) && CFGetTypeID(value) == CFNumberGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLParentDirectoryURLKey) && CFGetTypeID(value) == CFURLGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLVolumeURLKey) && CFGetTypeID(value) == CFURLGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLTypeIdentifierKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLLocalizedTypeDescriptionKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLLabelNumberKey) && CFGetTypeID(value) == CFNumberGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLLabelColorKey))
    {
        // not supported, and what is a CFColorRef anyhow? do they mean CGColorRef?
    }
    else if (CFEqual(key, kCFURLLocalizedLabelKey) && CFGetTypeID(value) == CFStringGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLEffectiveIconKey))
    {
        // not supported, go away!
    }
    else if (CFEqual(key, kCFURLCustomIconKey))
    {
        // same as prev
    }
    else if (CFEqual(key, kCFURLFileResourceIdentifierKey))
    {
        // NO
    }
    else if (CFEqual(key, kCFURLVolumeIdentifierKey))
    {
        // not supported
    }
    else if (CFEqual(key, kCFURLPreferredIOBlockSizeKey) && CFGetTypeID(value) == CFNumberGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsReadableKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsWritableKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLIsExecutableKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLFileSecurityKey) && [(id)value isKindOfClass:objc_getClass("NSFileSecurity")])
    {
        // Apply the owner, group and permission bits that are set; ACLs and UUIDs are ignored.
        // chown() clears the set-user-ID and set-group-ID bits, so the mode is applied after it.
        UInt8 path[PATH_MAX] = { 0 };
        CFFileSecurityRef security = (CFFileSecurityRef)value;
        uid_t owner; gid_t group; mode_t mode;
        Boolean hasOwner = CFFileSecurityGetOwner(security, &owner);
        Boolean hasGroup = CFFileSecurityGetGroup(security, &group);
        Boolean ok = CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX);
        if (ok && (hasOwner || hasGroup) && chown((const char *)path, hasOwner ? owner : (uid_t)-1, hasGroup ? group : (gid_t)-1) != 0)
            ok = false;
        if (ok && CFFileSecurityGetMode(security, &mode) && chmod((const char *)path, mode) != 0)
            ok = false;
        if (ok)
            acceptedValue = CFRetain(value);
        else
            posixError(error);
    }
    else if (CFEqual(key, kCFURLIsExcludedFromBackupKey) && CFGetTypeID(value) == CFBooleanGetTypeID())
    {
        acceptedValue = CFRetain(value);
    }
    else if (CFEqual(key, kCFURLFileResourceTypeKey))
    {
        // not supported
    }

    return acceptedValue;
}

Boolean CFURLSetResourcePropertyForKey(CFURLRef url, CFStringRef key, CFTypeRef propertyValue, CFErrorRef *error)
{
    CFMutableDictionaryRef resourceInfo = CFURLResourceInfo(url);

    CFTypeRef value = CFURLSetPropertyForKey(url, key, propertyValue, error);
    
    CFURLResourceInfoUpdateRelease(resourceInfo, key, value);

    if (value != NULL)
    {
        return true;
    }
    else
    {
        return false;
    }
}

struct URLPropertyContext {
    CFURLRef url;
    CFErrorRef *error;
    CFMutableDictionaryRef resourceInfo;
    Boolean *success;
};

static void applyProperties(const void *key, const void *value, void *context)
{
    struct URLPropertyContext *ctx = (struct URLPropertyContext *)context;
    if (!*ctx->success)
    {
        return;
    }

    CFTypeRef acceptedValue = CFURLSetPropertyForKey(ctx->url, key, value, ctx->error);
    if (acceptedValue != NULL)
    {
        CFURLResourceInfoUpdate(ctx->resourceInfo, key, acceptedValue);
        CFRelease(acceptedValue);
    }
    else
    {
        *ctx->success = false;
    }
}

Boolean CFURLSetResourcePropertiesForKeys(CFURLRef url, CFDictionaryRef keyedPropertyValues, CFErrorRef *error)
{
    Boolean success = true;
    CFMutableDictionaryRef resourceInfo = CFURLResourceInfo(url);
    struct URLPropertyContext ctx = {
        url,
        error,
        resourceInfo,
        &success
    };

    CFDictionaryApplyFunction(resourceInfo, &applyProperties, &ctx);
    CFURLResourceInfoRelease(resourceInfo);

    return success;
}

CFDataRef CFURLCreateBookmarkDataFromFile(CFAllocatorRef allocator, CFURLRef fileURL, CFErrorRef *errorRef)
{
#warning TODO: FIXME
    return NULL;
}

Boolean CFURLWriteBookmarkDataToFile(CFDataRef bookmarkRef, CFURLRef fileURL, CFURLBookmarkFileCreationOptions options, CFErrorRef *errorRef)
{
#warning TODO: FIXME
    return false;
}

// Bookmark data is opaque to callers and is not compatible with macOS bookmark data (it cannot be
// exchanged with a Mac). It is the four bytes "DLBK" and a binary property list of: the item's POSIX path,
// its path relative to the URL the bookmark was made relative to (when it lies below it), its inode
// number, and the resource values asked for. A URL that is not a file URL is kept as its string.
// Data that is a bare absolute path, what earlier versions made, still resolves.
static const UInt8 CFURLBookmarkMagic[4] = { 'D', 'L', 'B', 'K' };
static const CFStringRef CFURLBookmarkPathKey = CFSTR("path");
static const CFStringRef CFURLBookmarkRelativePathKey = CFSTR("relativePath");
static const CFStringRef CFURLBookmarkInodeKey = CFSTR("inode");
static const CFStringRef CFURLBookmarkURLKey = CFSTR("url");
static const CFStringRef CFURLBookmarkResourceValuesKey = CFSTR("resourceValues");
// A CFURL resource value is kept as a dictionary with its string under this key.
static const CFStringRef CFURLBookmarkURLValueKey = CFSTR("DLURL");

static void CFURLBookmarkSetSInt64(CFMutableDictionaryRef record, CFStringRef key, SInt64 number)
{
    CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &number);
    CFDictionarySetValue(record, key, value);
    CFRelease(value);
}

// The path of the item below the path of the URL the bookmark is made relative to (that path is taken as a
// directory), or NULL.
// GUESS: the documentation says relativeToURL is usually the document that owns the bookmark, which the
// item need not lie below; it does not say how the data is made relative. Only the case of an item below
// the URL is handled.
static CFStringRef CFURLBookmarkCopyRelativePath(CFURLRef relativeToURL, const UInt8 *path)
{
    UInt8 base[PATH_MAX] = { 0 };

    if (relativeToURL == NULL || !CFURLGetFileSystemRepresentation(relativeToURL, true, base, PATH_MAX))
    {
        return NULL;
    }

    size_t length = strlen((const char *)base);
    while (length > 0 && base[length - 1] == '/')
    {
        length--;
    }
    if (strncmp((const char *)path, (const char *)base, length) != 0 || path[length] != '/' || path[length + 1] == 0)
    {
        return NULL;
    }
    return CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, (const char *)path + length + 1);
}

// Only values a property list holds are kept, and a CFURL as a dictionary; any other kind is left out.
static CFTypeRef CFURLBookmarkCopyStorableValue(CFTypeRef value)
{
    CFTypeID type = CFGetTypeID(value);

    if (type == CFStringGetTypeID() || type == CFDataGetTypeID() || type == CFDateGetTypeID() ||
        type == CFNumberGetTypeID() || type == CFBooleanGetTypeID())
    {
        return CFRetain(value);
    }
    if (type == CFURLGetTypeID())
    {
        CFURLRef absolute = CFURLCopyAbsoluteURL((CFURLRef)value);
        CFTypeRef string = CFURLGetString(absolute);
        CFDictionaryRef wrapped = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&CFURLBookmarkURLValueKey, &string, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(absolute);
        return wrapped;
    }
    return NULL;
}

static CFTypeRef CFURLBookmarkCopyStoredValue(CFTypeRef value)
{
    if (CFGetTypeID(value) == CFDictionaryGetTypeID())
    {
        CFStringRef string = CFDictionaryGetValue((CFDictionaryRef)value, CFURLBookmarkURLValueKey);
        if (string != NULL && CFGetTypeID(string) == CFStringGetTypeID())
        {
            return CFURLCreateWithString(kCFAllocatorDefault, string, NULL);
        }
    }
    return CFRetain(value);
}

static void CFURLBookmarkCorruptError(CFErrorRef *error)
{
    if (error != NULL)
    {
        // GUESS: the documentation lists no error codes; 259 is NSFileReadCorruptFileError.
        *error = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainCocoa, 259, NULL);
    }
}

// The record's value for the key if it has the given type: bookmark data from outside is not trusted.
static CFTypeRef CFURLBookmarkGetValue(CFDictionaryRef record, CFStringRef key, CFTypeID type)
{
    CFTypeRef value = CFDictionaryGetValue(record, key);
    return (value != NULL && CFGetTypeID(value) == type) ? value : NULL;
}

// The record the data holds, or NULL (with an error) when it is not bookmark data.
static CFDictionaryRef CFURLBookmarkCopyRecord(CFDataRef bookmark, CFErrorRef *error)
{
    CFIndex length = CFDataGetLength(bookmark);
    const UInt8 *bytes = CFDataGetBytePtr(bookmark);
    CFDictionaryRef record = NULL;

    if (length > 0 && bytes[0] == '/')
    {
        CFStringRef path = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, length, kCFStringEncodingUTF8, false);
        if (path != NULL)
        {
            record = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&CFURLBookmarkPathKey, (const void **)&path, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFRelease(path);
        }
    }
    else if (length > (CFIndex)sizeof(CFURLBookmarkMagic) && memcmp(bytes, CFURLBookmarkMagic, sizeof(CFURLBookmarkMagic)) == 0)
    {
        CFDataRef list = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes + sizeof(CFURLBookmarkMagic), length - sizeof(CFURLBookmarkMagic), kCFAllocatorNull);
        CFPropertyListRef parsed = CFPropertyListCreateWithData(kCFAllocatorDefault, list, kCFPropertyListImmutable, NULL, NULL);
        CFRelease(list);
        if (parsed != NULL && CFGetTypeID(parsed) == CFDictionaryGetTypeID())
        {
            if (CFURLBookmarkGetValue(parsed, CFURLBookmarkPathKey, CFStringGetTypeID()) != NULL ||
                CFURLBookmarkGetValue(parsed, CFURLBookmarkURLKey, CFStringGetTypeID()) != NULL)
            {
                record = parsed;
                parsed = NULL;
            }
        }
        if (parsed != NULL)
        {
            CFRelease(parsed);
        }
    }

    if (record == NULL)
    {
        CFURLBookmarkCorruptError(error);
    }
    return record;
}

// Resolves to the URL of the item the record names: the path relative to relativeToURL and the absolute
// path are candidates, and the first one that has the recorded inode wins (else the first that exists).
// This system has no lookup of a file by its ID, so an item that moved is not found.
// The data is stale when the item found does not have the recorded inode. That is only a heuristic: the
// inode of a file saved by writing a new file and renaming it over the old one changes, and a file system
// may reuse the inode of a deleted file, so replacement is not always seen. The device number is not
// compared: it is not stable for every file system (a union or overlay file system hands out its own).
// GUESS: the documentation does not say when bookmark data is stale beyond "needs to be recreated".
// QUIRK: the data is also stale when the item is found at another path than the recorded one (for example a
// relative bookmark resolved against a moved directory), and a missing item is NSCocoaErrorDomain 4
// (NSFileNoSuchFileError), not 260. Not documented. Evidence: black-box observation on macOS 26.7.3 (x86_64),
// tier 2. Test: tests/nsurl-bookmark-data.m, "moved directory" and "A missing item".
CFURLRef CFURLCreateByResolvingBookmarkData(CFAllocatorRef allocator, CFDataRef bookmark, CFURLBookmarkResolutionOptions options, CFURLRef relativeToURL, CFArrayRef resourcePropertiesToInclude, Boolean* isStale, CFErrorRef* error)
{
    if (isStale != NULL)
        *isStale = false;
    if (error != NULL)
        *error = NULL;
    if (bookmark == NULL)
        return NULL;

    CFDictionaryRef record = CFURLBookmarkCopyRecord(bookmark, error);
    if (record == NULL)
        return NULL;

    CFURLRef result = NULL;
    CFStringRef urlString = CFURLBookmarkGetValue(record, CFURLBookmarkURLKey, CFStringGetTypeID());
    if (urlString != NULL)
    {
        result = CFURLCreateWithString(allocator, urlString, NULL);
        CFRelease(record);
        return result;
    }

    char candidates[2][PATH_MAX];
    int count = 0;
    CFStringRef relativePath = CFURLBookmarkGetValue(record, CFURLBookmarkRelativePathKey, CFStringGetTypeID());
    UInt8 base[PATH_MAX] = { 0 };
    if (relativePath != NULL && relativeToURL != NULL && CFURLGetFileSystemRepresentation(relativeToURL, true, base, PATH_MAX))
    {
        char relative[PATH_MAX];
        if (CFStringGetFileSystemRepresentation(relativePath, relative, sizeof(relative)) &&
            snprintf(candidates[count], PATH_MAX, "%s/%s", (const char *)base, relative) < PATH_MAX)
        {
            count++;
        }
    }
    CFStringRef path = CFURLBookmarkGetValue(record, CFURLBookmarkPathKey, CFStringGetTypeID());
    if (path != NULL && CFStringGetFileSystemRepresentation(path, candidates[count], PATH_MAX))
    {
        count++;
    }

    CFNumberRef inode = CFURLBookmarkGetValue(record, CFURLBookmarkInodeKey, CFNumberGetTypeID());
    SInt64 recordedInode = 0;
    Boolean knowsInode = inode != NULL && CFNumberGetValue(inode, kCFNumberSInt64Type, &recordedInode);
    int failure = ENOENT;
    int chosen = -1;
    Boolean matched = false;
    struct stat chosenInfo;
    for (int i = 0; i < count; i++)
    {
        struct stat info;
        if (lstat(candidates[i], &info) == -1)
        {
            failure = errno;
            continue;
        }

        Boolean identity = knowsInode && recordedInode == (SInt64)info.st_ino;
        if (chosen < 0 || (identity && !matched))
        {
            chosen = i;
            chosenInfo = info;
            matched = identity;
        }
        if (identity)
        {
            break;
        }
    }
    if (chosen >= 0)
    {
        if (isStale != NULL)
        {
            char recorded[PATH_MAX];
            Boolean samePath = path != NULL && CFStringGetFileSystemRepresentation(path, recorded, sizeof(recorded)) && strcmp(recorded, candidates[chosen]) == 0;
            *isStale = (knowsInode && !matched) || !samePath;
        }
        result = CFURLCreateFromFileSystemRepresentation(allocator, (const UInt8 *)candidates[chosen], strlen(candidates[chosen]), S_ISDIR(chosenInfo.st_mode));
    }
    if (result == NULL)
    {
        if (failure == ENOENT || failure == ENOTDIR)
        {
            if (error != NULL)
            {
                CFErrorRef underlying = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, failure, NULL);
                const CFStringRef keys[1] = { kCFErrorUnderlyingErrorKey };
                CFTypeRef values[1] = { underlying };
                *error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainCocoa, 4 /* NSFileNoSuchFileError */, (const void *const *)keys, (const void *const *)values, 1);
                CFRelease(underlying);
            }
        }
        else
        {
            cocoaReadError(error, failure);
        }
    }
    CFRelease(record);
    return result;
}

// A bookmark of an item that does not exist is not made, and neither is one of an item whose path is not
// valid UTF-8 (the path is kept as a string).
// GUESS: the documentation only says that failure returns nil; the errors reported here are 260
// (NSFileReadNoSuchFileError) for a missing item and 256 (NSFileReadUnknownError) for the other cases.
CFDataRef CFURLCreateBookmarkData(CFAllocatorRef allocator, CFURLRef url, CFURLBookmarkCreationOptions options, CFArrayRef resourcePropertiesToInclude, CFURLRef relativeToURL, CFErrorRef *error)
{
    if (error != NULL)
        *error = NULL;
    if (url == NULL)
        return NULL;

    CFMutableDictionaryRef record = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFStringRef scheme = CFURLCopyScheme(url);
    Boolean isFile = scheme != NULL && CFStringCompare(scheme, CFSTR("file"), kCFCompareCaseInsensitive) == kCFCompareEqualTo;
    if (scheme != NULL)
        CFRelease(scheme);

    if (!isFile)
    {
        // A URL that is not a file URL is kept alone: the options and keys do not apply.
        CFURLRef absolute = CFURLCopyAbsoluteURL(url);
        CFDictionarySetValue(record, CFURLBookmarkURLKey, CFURLGetString(absolute));
        CFRelease(absolute);
    }
    else
    {
        UInt8 path[PATH_MAX] = { 0 };
        struct stat info;
        int failure = EINVAL;
        Boolean found = false;
        if (CFURLGetFileSystemRepresentation(url, true, path, PATH_MAX))
        {
            found = lstat((const char *)path, &info) != -1;
            if (!found)
            {
                failure = errno;
            }
        }
        if (found)
        {
            // NULL when the path is not valid UTF-8.
            CFStringRef pathString = CFStringCreateWithFileSystemRepresentation(kCFAllocatorDefault, (const char *)path);
            if (pathString == NULL)
            {
                failure = EILSEQ;
            }
            else
            {
                CFDictionarySetValue(record, CFURLBookmarkPathKey, pathString);
                CFRelease(pathString);
            }
            CFURLBookmarkSetSInt64(record, CFURLBookmarkInodeKey, (SInt64)info.st_ino);

            CFStringRef relativePath = CFURLBookmarkCopyRelativePath(relativeToURL, path);
            if (relativePath != NULL)
            {
                CFDictionarySetValue(record, CFURLBookmarkRelativePathKey, relativePath);
                CFRelease(relativePath);
            }

            // QUIRK: the name and the directory flag are stored whether or not they were asked for. Not documented.
            // Evidence: black-box observation on macOS 26.7.3 (x86_64), tier 2: resourceValuesForKeys:fromBookmarkData:
            // returns them for data made with no keys. Test: tests/nsurl-bookmark-data.m, "default values".
            {
                CFIndex requested = resourcePropertiesToInclude != NULL ? CFArrayGetCount(resourcePropertiesToInclude) : 0;
                CFIndex keyCount = requested + 2;
                CFMutableDictionaryRef values = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                for (CFIndex i = 0; i < keyCount; i++)
                {
                    CFStringRef key = i < requested ? CFArrayGetValueAtIndex(resourcePropertiesToInclude, i)
                        : (i == requested ? kCFURLNameKey : kCFURLIsDirectoryKey);
                    CFTypeRef value = NULL;
                    if (CFURLCopyResourcePropertyForKey(url, key, &value, NULL) && value != NULL)
                    {
                        CFTypeRef storable = CFURLBookmarkCopyStorableValue(value);
                        if (storable != NULL)
                        {
                            CFDictionarySetValue(values, key, storable);
                            CFRelease(storable);
                        }
                        CFRelease(value);
                    }
                }
                CFDictionarySetValue(record, CFURLBookmarkResourceValuesKey, values);
                CFRelease(values);
            }
        }
        if (CFDictionaryGetValue(record, CFURLBookmarkPathKey) == NULL)
        {
            cocoaReadError(error, failure);
            CFRelease(record);
            return NULL;
        }
    }

    CFDataRef list = CFPropertyListCreateData(kCFAllocatorDefault, record, kCFPropertyListBinaryFormat_v1_0, 0, error);
    CFRelease(record);
    if (list == NULL)
    {
        return NULL;
    }
    CFMutableDataRef data = CFDataCreateMutable(allocator, 0);
    CFDataAppendBytes(data, CFURLBookmarkMagic, sizeof(CFURLBookmarkMagic));
    CFDataAppendBytes(data, CFDataGetBytePtr(list), CFDataGetLength(list));
    CFRelease(list);
    return data;
}

// The resource values stored in the data, without resolving it.
static CFDictionaryRef CFURLBookmarkCopyResourceValues(CFDataRef bookmark)
{
    if (bookmark == NULL)
    {
        return NULL;
    }
    CFDictionaryRef record = CFURLBookmarkCopyRecord(bookmark, NULL);
    CFDictionaryRef values = record != NULL ? CFURLBookmarkGetValue(record, CFURLBookmarkResourceValuesKey, CFDictionaryGetTypeID()) : NULL;
    if (values != NULL)
    {
        CFRetain(values);
    }
    if (record != NULL)
    {
        CFRelease(record);
    }
    return values;
}

CFTypeRef CFURLCreateResourcePropertyForKeyFromBookmarkData(CFAllocatorRef allocator, CFStringRef resourcePropertyToReturn, CFDataRef bookmark)
{
    if (resourcePropertyToReturn == NULL)
    {
        return NULL;
    }
    CFTypeRef result = NULL;
    CFDictionaryRef values = CFURLBookmarkCopyResourceValues(bookmark);
    CFTypeRef stored = values != NULL ? CFDictionaryGetValue(values, resourcePropertyToReturn) : NULL;

    if (stored != NULL)
    {
        result = CFURLBookmarkCopyStoredValue(stored);
    }
    if (values != NULL)
    {
        CFRelease(values);
    }
    return result;
}

CFDictionaryRef CFURLCreateResourcePropertiesForKeysFromBookmarkData(CFAllocatorRef allocator, CFArrayRef resourcePropertiesToReturn, CFDataRef bookmark)
{
    if (bookmark == NULL)
    {
        return NULL;
    }
    CFDictionaryRef record = CFURLBookmarkCopyRecord(bookmark, NULL);
    if (record == NULL)
    {
        return NULL;
    }

    CFDictionaryRef values = CFURLBookmarkGetValue(record, CFURLBookmarkResourceValuesKey, CFDictionaryGetTypeID());
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(allocator, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFIndex count = resourcePropertiesToReturn != NULL ? CFArrayGetCount(resourcePropertiesToReturn) : 0;
    for (CFIndex i = 0; values != NULL && i < count; i++)
    {
        CFStringRef key = CFArrayGetValueAtIndex(resourcePropertiesToReturn, i);
        CFTypeRef stored = CFDictionaryGetValue(values, key);
        if (stored != NULL)
        {
            CFTypeRef value = CFURLBookmarkCopyStoredValue(stored);
            if (value != NULL)
            {
                CFDictionarySetValue(result, key, value);
                CFRelease(value);
            }
        }
    }
    CFRelease(record);
    return result;
}

Boolean CFURLResourceIsReachable(CFURLRef url, CFErrorRef *error)
{
    if (error != NULL)
        *error = NULL;
    if (url == NULL)
        return false;
    CFStringRef path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
    if (path == NULL)
        return false;
    char cpath[PATH_MAX];
    Boolean ok = CFStringGetCString(path, cpath, sizeof(cpath), kCFStringEncodingUTF8);
    CFRelease(path);
    if (!ok)
        return false;
    if (access(cpath, F_OK) == 0)
        return true;
    cocoaReadError(error, errno);
    return false;
}

// Hands the CFError a CoreFoundation function created (it is owned by the caller) to an NSError ** as an
// autoreleased NSError, or drops it when the caller does not want it.
static void CFURLReturnError(CFErrorRef cfError, NSError **error)
{
    if (error != NULL)
    {
        *error = [(NSError *)cfError autorelease];
    }
    else if (cfError != NULL)
    {
        CFRelease(cfError);
    }
}

@implementation NSURL

@dynamic dataRepresentation; // implemented in Foundation's NSURL category, built on CFURLCreateData


+ (NSData *)bookmarkDataWithContentsOfURL:(NSURL *)bookmarkFileURL error:(NSError **)error
{
    return [(NSData *)CFURLCreateBookmarkDataFromFile(kCFAllocatorDefault, (CFURLRef)bookmarkFileURL, (CFErrorRef *)error) autorelease];
}

+ (BOOL)writeBookmarkData:(NSData *)bookmarkData toURL:(NSURL *)bookmarkFileURL options:(NSURLBookmarkFileCreationOptions)options error:(NSError **)error
{
    return CFURLWriteBookmarkDataToFile((CFDataRef)bookmarkData, (CFURLRef)bookmarkFileURL, options, (CFErrorRef *)error);
}

+ (NSDictionary *)resourceValuesForKeys:(NSArray *)keys fromBookmarkData:(NSData *)bookmarkData
{
    return [(NSDictionary *)CFURLCreateResourcePropertiesForKeysFromBookmarkData(kCFAllocatorDefault, (CFArrayRef)keys, (CFDataRef)bookmarkData) autorelease];
}

+ (id)URLByResolvingBookmarkData:(NSData *)bookmarkData options:(NSURLBookmarkResolutionOptions)options relativeToURL:(NSURL *)relativeURL bookmarkDataIsStale:(BOOL *)isStale error:(NSError **)error
{
    return [[[self alloc] initByResolvingBookmarkData:bookmarkData options:options relativeToURL:relativeURL bookmarkDataIsStale:isStale error:error] autorelease];
}

// QUIRK: an item that is not an alias file resolves to the URL given, without an error (also a
// directory, a missing item and a non-file URL), and a symbolic link resolves to its target.
// The documentation only describes resolving real alias files. Evidence: black-box observation
// on Mac OS X 10.14.4 and macOS 26.7.3 (tier 2), vd-upstream MC-NSURL-V430A. Alias files made
// by writeBookmarkData:toURL:options:error: are not supported here, so the quirk is the whole
// behaviour. Test: nsurl-alias-file-resolution.
+ (id)URLByResolvingAliasFileAtURL:(NSURL *)url options:(NSURLBookmarkResolutionOptions)options error:(NSError **)error
{
    if (error != NULL)
    {
        *error = nil;
    }
    if (url == nil)
    {
        return nil;
    }

    UInt8 path[PATH_MAX] = { 0 };
    char target[PATH_MAX];
    struct stat info;
    if (![url isFileURL] || !CFURLGetFileSystemRepresentation((CFURLRef)url, true, path, PATH_MAX) || lstat((const char *)path, &info) != 0 || !S_ISLNK(info.st_mode))
    {
        return url;
    }

    ssize_t length = readlink((const char *)path, target, sizeof(target) - 1);
    if (length <= 0)
    {
        return url;
    }
    target[length] = 0;

    // A relative target is relative to the directory that holds the link.
    char joined[PATH_MAX];
    if (target[0] == '/')
    {
        if (strlcpy(joined, target, sizeof(joined)) >= sizeof(joined))
        {
            return url;
        }
    }
    else
    {
        char *slash = strrchr((const char *)path, '/');
        size_t directoryLength = slash != NULL ? (size_t)(slash - (char *)path) + 1 : 0;
        if (directoryLength + strlen(target) >= sizeof(joined))
        {
            return url;
        }
        memcpy(joined, path, directoryLength);
        strlcpy(joined + directoryLength, target, sizeof(joined) - directoryLength);
    }

    struct stat targetInfo;
    Boolean isDirectory = stat(joined, &targetInfo) == 0 && S_ISDIR(targetInfo.st_mode);
    CFURLRef resolved = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)joined, strlen(joined), isDirectory);
    return [(NSURL *)resolved autorelease];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)bookmarkDataWithAliasRecord:(id)aliasRecord
{
    return nil; // what is this used for? it seems to do absolutely nothing on iOS
}

- (id)initByResolvingBookmarkData:(NSData *)bookmarkData options:(NSURLBookmarkResolutionOptions)options relativeToURL:(NSURL *)relativeURL bookmarkDataIsStale:(BOOL *)isStale error:(NSError **)error
{
    [self release];
    Boolean stale = NO;
    CFErrorRef cfError = NULL;
    CFURLRef relative = [relativeURL _cfurl];
    CFURLRef url = CFURLCreateByResolvingBookmarkData(kCFAllocatorDefault, (CFDataRef)bookmarkData, options, relative, NULL, &stale, &cfError);
    CFURLReturnError(cfError, error);

    if (isStale)
    {
        *isStale = stale;
    }

    return (NSURL *)url;
}

- (NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options includingResourceValuesForKeys:(NSArray *)keys relativeToURL:(NSURL *)relativeURL error:(NSError **)error
{
    CFErrorRef cfError = NULL;
    NSData *data = (NSData *)CFURLCreateBookmarkData(kCFAllocatorDefault, [self _cfurl], options, (CFArrayRef)keys, (CFURLRef)relativeURL, &cfError);
    CFURLReturnError(cfError, error);
    return [data autorelease];
}

- (NSURL *)filePathURL
{
    NSURL *url = nil;
    if ([self isFileReferenceURL])
    {
        url = [(NSURL *)CFURLCreateFilePathURL(kCFAllocatorDefault, [self _cfurl], NULL) autorelease];
    }
    else if ([self isFileURL])
    {
        url = self;
    }

    return url;
}

- (NSURL *)fileReferenceURL
{
    NSURL *url = nil;
    if ([self isFileReferenceURL])
    {
        url = self;
    }
    else if ([self isFileURL])
    {
        url = [(NSURL *)CFURLCreateFileReferenceURL(kCFAllocatorDefault, [self _cfurl], NULL) autorelease];
    }
    
    return url;
}

- (BOOL)isFileReferenceURL
{
    return _CFURLIsFileReferenceURL([self _cfurl]);
}

- (BOOL)startAccessingSecurityScopedResource
{
    return YES;
}

- (void)stopAccessingSecurityScopedResource
{
}

- (BOOL)checkResourceIsReachableAndReturnError:(NSError **)error
{
    return CFURLResourceIsReachable([self _cfurl], (CFErrorRef *)error);
}

- (BOOL)getResourceValue:(out id *)value forKey:(NSString *)key error:(out NSError **)error
{
    CFTypeRef owned = NULL;
    BOOL ok = CFURLCopyResourcePropertyForKey([self _cfurl], (CFStringRef)key, &owned, (CFErrorRef *)error);
    if (value != NULL)
    {
        *value = [(id)owned autorelease];
    }
    else
    {
        [(id)owned release];
    }
    return ok;
}

- (NSDictionary *)resourceValuesForKeys:(NSArray *)keys error:(NSError **)error
{
    return [(NSDictionary *)CFURLCopyResourcePropertiesForKeys([self _cfurl], (CFArrayRef)keys, (CFErrorRef *)error) autorelease];
}

- (BOOL)setResourceValue:(id)value forKey:(NSString *)key error:(NSError **)error
{
    return CFURLSetResourcePropertyForKey([self _cfurl], (CFStringRef)key, (CFTypeRef)value, (CFErrorRef *)error);
}

- (BOOL)setResourceValues:(NSDictionary *)keyedValues error:(NSError **)error
{
    return CFURLSetResourcePropertiesForKeys([self _cfurl], (CFDictionaryRef)keyedValues, (CFErrorRef *)error);
}

- (void)removeCachedResourceValueForKey:(NSURLResourceKey)key
{
    CFURLRemoveCachedResourceValue([self _cfurl], (CFStringRef)key);
}

- (void)removeAllCachedResourceValues
{
    CFURLRemoveAllCachedResourceValues([self _cfurl]);
}

- (void)setTemporaryResourceValue:(id)value forKey:(NSURLResourceKey)key
{
    CFURLSetTemporaryResourceValue([self _cfurl], (CFStringRef)key, (CFTypeRef)value);
}

// A promised item is one whose content a file provider may still have to deliver; here every
// item is present or absent, so reachability and the resource values are those of the item.
- (BOOL)checkPromisedItemIsReachableAndReturnError:(NSError **)error
{
    return CFURLResourceIsReachable([self _cfurl], (CFErrorRef *)error);
}

- (NSDictionary *)promisedItemResourceValuesForKeys:(NSArray *)keys error:(NSError **)error
{
    if (![self checkPromisedItemIsReachableAndReturnError:error])
    {
        return nil;
    }
    return [self resourceValuesForKeys:keys error:error];
}

@end
