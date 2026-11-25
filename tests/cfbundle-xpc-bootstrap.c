// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: _CFBundleSetupXPCBootstrap and
// _CFBundleSetupXPCBootstrapWithLanguages. Observed on macOS 26.7.3 (x86_64)
// with the same calls: the bootstrap dictionary gets an "_NSBundleEntry"
// dictionary whose "MainBundleLanguages" array holds the given languages, or
// for the plain function the main bundle's (one language for a tool), and
// the dictionary's other entries stay.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <xpc/xpc.h>

extern void _CFBundleSetupXPCBootstrap(xpc_object_t);
extern void _CFBundleSetupXPCBootstrapWithLanguages(xpc_object_t, CFArrayRef);

static int failures;

static void report(const char *name, int ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static xpc_object_t languagesIn(xpc_object_t bootstrap)
{
    xpc_object_t entry = xpc_dictionary_get_value(bootstrap, "_NSBundleEntry");
    if (entry == NULL || xpc_get_type(entry) != XPC_TYPE_DICTIONARY)
        return NULL;
    xpc_object_t languages = xpc_dictionary_get_value(entry, "MainBundleLanguages");
    return languages != NULL && xpc_get_type(languages) == XPC_TYPE_ARRAY ? languages : NULL;
}

int main(void)
{
    xpc_object_t plain = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(plain, "keep", "me");
    _CFBundleSetupXPCBootstrap(plain);
    xpc_object_t languages = languagesIn(plain);
    report("main bundle languages", languages != NULL && xpc_array_get_count(languages) == 1
           && xpc_array_get_string(languages, 0) != NULL);
    const char *kept = xpc_dictionary_get_string(plain, "keep");
    report("other entries stay", kept != NULL && strcmp(kept, "me") == 0);

    const void *given[] = { CFSTR("fr"), CFSTR("de") };
    CFArrayRef array = CFArrayCreate(NULL, given, 2, &kCFTypeArrayCallBacks);
    xpc_object_t withLanguages = xpc_dictionary_create(NULL, NULL, 0);
    _CFBundleSetupXPCBootstrapWithLanguages(withLanguages, array);
    languages = languagesIn(withLanguages);
    report("given languages", languages != NULL && xpc_array_get_count(languages) == 2
           && strcmp(xpc_array_get_string(languages, 0), "fr") == 0 && strcmp(xpc_array_get_string(languages, 1), "de") == 0);

    CFRelease(array);
    xpc_release(withLanguages);
    xpc_release(plain);
    return failures != 0;
}
