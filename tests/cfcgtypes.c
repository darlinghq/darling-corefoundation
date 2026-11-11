/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CoreFoundation.h provides the Core Graphics geometry types on its own, so
 * clients that never import CoreGraphics can use CGFloat, CGPoint, CGSize,
 * CGVector and CGRect. The CFString tokenizer is part of the same umbrella.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

#ifndef CF_DEFINES_CG_TYPES
#error CoreFoundation.h must define CF_DEFINES_CG_TYPES
#endif
#ifndef CGFLOAT_DEFINED
#error CoreFoundation.h must define CGFLOAT_DEFINED
#endif

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); ++failures; } } while (0)

int main(void) {
#if defined(__LP64__) && __LP64__
    CHECK(sizeof(CGFloat) == sizeof(double));
    CHECK(CGFLOAT_IS_DOUBLE == 1);
#else
    CHECK(sizeof(CGFloat) == sizeof(float));
    CHECK(CGFLOAT_IS_DOUBLE == 0);
#endif
    CHECK(sizeof(CGPoint) == 2 * sizeof(CGFloat));
    CHECK(sizeof(CGSize) == 2 * sizeof(CGFloat));
    CHECK(sizeof(CGVector) == 2 * sizeof(CGFloat));
    CHECK(sizeof(CGRect) == 4 * sizeof(CGFloat));

    CGRect r = { { 1, 2 }, { 3, 4 } };
    CHECK(r.origin.x == 1 && r.origin.y == 2 && r.size.width == 3 && r.size.height == 4);
    CGVector v = { 5, 6 };
    CHECK(v.dx == 5 && v.dy == 6);
    CHECK(CGFLOAT_MAX > CGFLOAT_MIN && CGFLOAT_EPSILON > 0);

    /* The tokenizer declarations come with the umbrella header. */
    CFStringTokenizerRef t = CFStringTokenizerCreate(kCFAllocatorDefault, CFSTR("a b"),
        CFRangeMake(0, 3), kCFStringTokenizerUnitWord, NULL);
    CHECK(t != NULL);
    if (t) CFRelease(t);

    printf("%s\n", failures ? "FAILED" : "PASS");
    return failures != 0;
}
