#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, \
        (const void *)(unsigned long)&_replacee \
    };

static int hook_backtrace(void **array, int size) {
    const char *mode = getenv("TEST_BACKTRACE_MODE");
    if (mode != NULL) {
        if (mode[0] == '0')
            return 0;
        if (mode[0] == '1') {
            if (size > 0)
                array[0] = (void *)0x1000;
            return 1;
        }
        if (mode[0] == '2' || mode[0] == 'n') {
            if (size >= 2) {
                array[0] = (void *)0x1000;
                array[1] = (void *)0x2000;
                return 2;
            }
        }
    }
    return backtrace(array, size);
}

static char **hook_backtrace_symbols(void *const *array, int size) {
    const char *mode = getenv("TEST_BACKTRACE_MODE");
    if (mode != NULL) {
        if (mode[0] == 'n')
            return NULL;
        if (mode[0] == '2') {
            static char frame0[] = "0 ok";
            static char frame1[] = "\xff\xfe\x80"; /* invalid UTF-8 */
            char **res = malloc((size_t)size * sizeof(char *));
            if (res == NULL)
                return NULL;
            for (int i = 0; i < size; i++)
                res[i] = (i == 1) ? frame1 : frame0;
            return res;
        }
    }
    return backtrace_symbols(array, size);
}

DYLD_INTERPOSE(hook_backtrace, backtrace)
DYLD_INTERPOSE(hook_backtrace_symbols, backtrace_symbols)
