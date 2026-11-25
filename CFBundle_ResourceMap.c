// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Lubos Dolezel
//
// The Resource Manager bridge of CFBundle (deprecated): opening the resource map of a bundle. Bundles here keep
// their resources in files, not in resource forks, and no Resource Manager maps are made, so the calls behave as
// they do on macOS for a bundle that has no resource files: no map.

#include <CoreFoundation/CFBundle.h>

// The documented result when the bundle has no resource map to open: -1 (observed for application bundles and
// frameworks without resource forks on macOS 26.7.3 and 10.14.4).
CFBundleRefNum CFBundleOpenBundleResourceMap(CFBundleRef bundle) {
    (void) bundle;
    return -1;
}

// The result of the call is the Resource Manager error resFNotFound (-193) when the bundle has no resource files,
// and both reference numbers are -1 (observed on macOS 26.7.3 and 10.14.4).
SInt32 CFBundleOpenBundleResourceFiles(CFBundleRef bundle, CFBundleRefNum *refNum, CFBundleRefNum *localizedRefNum) {
    (void) bundle;
    if (refNum != NULL)
        *refNum = -1;
    if (localizedRefNum != NULL)
        *localizedRefNum = -1;
    return -193;
}

// Closing a map that was never opened (-1 or any other number) does nothing.
void CFBundleCloseBundleResourceMap(CFBundleRef bundle, CFBundleRefNum refNum) {
    (void) bundle;
    (void) refNum;
}
