/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Registers the CFURLComponents runtime class defined by the
 * swift-corelibs-foundation sources compiled from submodules/.
 */
#include "CFRuntime.h"
#include <dispatch/dispatch.h>

extern const CFRuntimeClass __CFURLComponentsClass;

CF_PRIVATE CFTypeID __CFURLComponentsRegisterClass(void) {
    static CFTypeID typeID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ typeID = _CFRuntimeRegisterClass(&__CFURLComponentsClass); });
    return typeID;
}
