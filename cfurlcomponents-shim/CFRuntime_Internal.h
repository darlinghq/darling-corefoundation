/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Stand-in for the swift-corelibs-foundation CFRuntime_Internal.h, which the
 * unmodified CFURLComponents.c from submodules/swift-corelibs-foundation
 * includes. This tree registers CF classes lazily, so the fixed type ID that
 * the upstream header provides is replaced by a registration call.
 */
#ifndef DARLING_CFURLCOMPONENTS_RUNTIME_INTERNAL_H
#define DARLING_CFURLCOMPONENTS_RUNTIME_INTERNAL_H

#include "CFRuntime.h"

#ifndef CF_CROSS_PLATFORM_EXPORT
#define CF_CROSS_PLATFORM_EXPORT extern
#endif

CF_PRIVATE CFTypeID __CFURLComponentsRegisterClass(void);
#define _kCFRuntimeIDCFURLComponents __CFURLComponentsRegisterClass()

#endif
