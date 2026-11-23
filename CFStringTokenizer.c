//
//  CFStringTokenizer.c
//  CoreFoundation
//
//  Copyright (c) 2014 Apportable. All rights reserved.
//

#include "CFBase.h"
#include "CFRuntime.h"
#include "CFStringTokenizer.h"
#include <stdlib.h>
#include <unicode/ubrk.h>
#include <unicode/uchar.h>
#include <unicode/ustring.h>
#include <unicode/utf16.h>

#define TYPE_MASK 0x000000FF

struct __CFStringTokenizer {
    CFRuntimeBase _base;
    CFStringRef _string;
    CFRange _range;
    CFOptionFlags _options;
    CFLocaleRef _locale;
    UBreakIterator *_break_itr;
    UChar *_text; // owned UTF-16 text; the break iterator keeps a pointer to it
    CFRange _token; // the current token, {kCFNotFound, 0} when there is none
};

static void __CFStringTokenizerDeallocate(CFTypeRef cf) {
    struct __CFStringTokenizer *tokenizer = (struct __CFStringTokenizer *)cf;
    if (tokenizer->_string) {
        CFRelease(tokenizer->_string);
    }

    if (tokenizer->_locale) {
        CFRelease(tokenizer->_locale);
    }

    if (tokenizer->_break_itr) {
        ubrk_close(tokenizer->_break_itr);
    }

    free(tokenizer->_text);
}

static UChar *__CFStringTokenizerCopyText(CFStringRef string, CFIndex len) {
    UChar *text = malloc((len + 1) * sizeof(UChar));
    if (text == NULL) {
        return NULL;
    }
    CFStringGetCharacters(string, CFRangeMake(0, len), (UniChar *)text);
    text[len] = 0;
    return text;
}

// GUESS: a paragraph token runs up to and including its separator, and the separators are CR, LF,
// CRLF and U+2029 (not NEL or U+2028). The separator set is the one CFStringGetParagraphBounds uses
// in this repository (isALineSeparatorTypeCharacter with includeLineEndings false, CFString.c)
// and documents publicly; the tokenizer reference says neither for the paragraph unit.
static UBreakIterator *__CFStringTokenizerOpenParagraphIterator(const UChar *text, CFIndex len) {
    static const char rules[] = "$Sep = [\\u000A\\u000D\\u2029];\n"
                                "[^$Sep]* (\\u000D \\u000A | $Sep) | [^$Sep]+;\n";
    UChar urules[sizeof(rules)];
    u_uastrcpy(urules, rules);
    UParseError parseError;
    UErrorCode err = U_ZERO_ERROR;
    return ubrk_openRules(urules, -1, text, len, &parseError, &err);
}

static CFStringTokenizerTokenType __CFStringTokenizerInvalidateToken(struct __CFStringTokenizer *tokenizer) {
    tokenizer->_token = CFRangeMake(kCFNotFound, 0);
    return kCFStringTokenizerTokenNone;
}

static Boolean __CFStringTokenizerHasDigit(const UChar *text, int32_t start, int32_t end) {
    int32_t i = start;
    while (i < end) {
        UChar32 c;
        U16_NEXT(text, i, end, c);
        if (u_isdigit(c)) {
            return true;
        }
    }
    return false;
}

// Classifies the segment [start, end) the break iterator just produced; status is its ICU rule
// status. Returns kCFStringTokenizerTokenNone for a segment that is not a token of the unit.
// GUESS: kCFStringTokenizerUnitWord skips the segments ICU gives no word status (white space,
// punctuation, symbols); the reference only says that UnitWordBoundary also returns the space
// between words. The number mask ("appears to contain a number") is set for a token that
// contains a decimal digit (general category Nd), for both word units.
static CFStringTokenizerTokenType __CFStringTokenizerSegmentType(struct __CFStringTokenizer *tokenizer, int32_t status, int32_t start, int32_t end) {
    CFOptionFlags unit = tokenizer->_options & TYPE_MASK;
    if (unit != kCFStringTokenizerUnitWord && unit != kCFStringTokenizerUnitWordBoundary) {
        return kCFStringTokenizerTokenNormal;
    }

    if (status >= UBRK_WORD_NONE && status < UBRK_WORD_NONE_LIMIT && unit == kCFStringTokenizerUnitWord) {
        return kCFStringTokenizerTokenNone;
    }
    if (__CFStringTokenizerHasDigit(tokenizer->_text, start, end)) {
        return kCFStringTokenizerTokenNormal | kCFStringTokenizerTokenHasHasNumbersMask;
    }
    return kCFStringTokenizerTokenNormal;
}

static CFTypeID __kCFStringTokenizerTypeID = _kCFRuntimeNotATypeID;

static const CFRuntimeClass __CFStringTokenizerClass = {
    _kCFRuntimeScannedObject,
    "CFStringTokenizer",
    NULL,   // init
    NULL,   // copy
    __CFStringTokenizerDeallocate,
    NULL,   // __CFStringTokenizerEqual,
    NULL,   // __CFStringTokenizerHash,
    NULL,   // 
    NULL
};

void __CFStringTokenizerInitialize(void) {
    __kCFStringTokenizerTypeID = _CFRuntimeRegisterClass(&__CFStringTokenizerClass);
}


CFTypeID CFStringTokenizerGetTypeID(void) {
    if (__kCFStringTokenizerTypeID == _kCFRuntimeNotATypeID) {
        __CFStringTokenizerInitialize();
    }
    return __kCFStringTokenizerTypeID;
}

#define BUFFER_SIZE 768

CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef allocator, CFStringRef string, CFRange range, CFOptionFlags options, CFLocaleRef locale) {
    CFIndex size = sizeof(struct __CFStringTokenizer) - sizeof(CFRuntimeBase);
    struct __CFStringTokenizer *tokenizer = (struct __CFStringTokenizer *)_CFRuntimeCreateInstance(allocator, CFStringTokenizerGetTypeID(), size, NULL);
    tokenizer->_string = CFStringCreateCopy(allocator, string);
    tokenizer->_range = range;
    tokenizer->_options = options;
    if (locale == NULL) {
        tokenizer->_locale = CFLocaleCopyCurrent();
    } else {
        tokenizer->_locale = CFRetain(locale);
    }


    CFStringRef localeName = locale ? CFLocaleGetIdentifier(locale) : CFSTR("");
    char buffer[BUFFER_SIZE];
    const char *cstr = CFStringGetCStringPtr(localeName, kCFStringEncodingASCII);
    if (NULL == cstr) {
        if (CFStringGetCString(localeName, buffer, BUFFER_SIZE, kCFStringEncodingASCII)) {
            cstr = buffer;
        }
    }

    if (NULL == cstr) {
        CFRelease((CFTypeRef)tokenizer);
        return NULL;
    }

    UBreakIteratorType type;
    // UBRK_CHARACTER, UBRK_WORD, UBRK_LINE, UBRK_SENTENCE
    switch (options & TYPE_MASK) { // mask off the high bits since they can be options
        case kCFStringTokenizerUnitWord:
        case kCFStringTokenizerUnitWordBoundary:
            type = UBRK_WORD;
            break;
        case kCFStringTokenizerUnitSentence:
            type = UBRK_SENTENCE;
            break;
        case kCFStringTokenizerUnitParagraph: // opened from rules below
            break;
        case kCFStringTokenizerUnitLineBreak:
            type = UBRK_LINE;
            break;
    }

    CFIndex len = CFStringGetLength(string);
    tokenizer->_text = __CFStringTokenizerCopyText(string, len);
    if (tokenizer->_text == NULL) {
        CFRelease(tokenizer);
        return NULL;
    }
    if ((options & TYPE_MASK) == kCFStringTokenizerUnitParagraph) {
        tokenizer->_break_itr = __CFStringTokenizerOpenParagraphIterator(tokenizer->_text, len);
    } else {
        UErrorCode err = U_ZERO_ERROR;
        tokenizer->_break_itr = ubrk_open(type, cstr, tokenizer->_text, len, &err);
    }

    if (tokenizer->_break_itr == NULL) {
        CFRelease(tokenizer);
        return NULL;
    }

    __CFStringTokenizerInvalidateToken(tokenizer);
    return tokenizer;
}

CFStringRef CFStringTokenizerCopyBestStringLanguage(CFStringRef string, CFRange range) {
	(void)string;
	(void)range;
	return NULL;
}

void CFStringTokenizerSetString(CFStringTokenizerRef tokenizer, CFStringRef string, CFRange range) {

#warning TODO: range is not handled currently

    CFIndex len = CFStringGetLength(string);
    UChar *text = __CFStringTokenizerCopyText(string, len);
    if (text == NULL) {
        return;
    }
    UErrorCode err = U_ZERO_ERROR;
    ubrk_setText(tokenizer->_break_itr, text, len, &err);
    if (U_FAILURE(err)) {
        free(text);
        return;
    }
    free(tokenizer->_text);
    tokenizer->_text = text;
    __CFStringTokenizerInvalidateToken(tokenizer);
}

CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index) {
    if (index < 0) {
        return __CFStringTokenizerInvalidateToken(tokenizer);
    }
    int32_t end = ubrk_following(tokenizer->_break_itr, index);
    if (end == UBRK_DONE) {
        return __CFStringTokenizerInvalidateToken(tokenizer);
    }

    // the status describes the segment that ends at end; read it before moving the iterator
    int32_t status = ubrk_getRuleStatus(tokenizer->_break_itr);
    int32_t start = ubrk_previous(tokenizer->_break_itr);
    ubrk_next(tokenizer->_break_itr);
    CFStringTokenizerTokenType type = __CFStringTokenizerSegmentType(tokenizer, status, start, end);
    if (type == kCFStringTokenizerTokenNone) {
        // GUESS: an index inside a segment the unit skips finds no token and leaves the iterator after that segment.
        return __CFStringTokenizerInvalidateToken(tokenizer);
    }

    tokenizer->_token = CFRangeMake(start, end - start);
    return type;
}

CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer) {
    for (;;) {
        int32_t start = ubrk_current(tokenizer->_break_itr);
        int32_t end = ubrk_next(tokenizer->_break_itr);
        if (end == UBRK_DONE) {
            return __CFStringTokenizerInvalidateToken(tokenizer);
        }

        CFStringTokenizerTokenType type = __CFStringTokenizerSegmentType(tokenizer, ubrk_getRuleStatus(tokenizer->_break_itr), start, end);
        if (type != kCFStringTokenizerTokenNone) {
            tokenizer->_token = CFRangeMake(start, end - start);
            return type;
        }
    }
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer) {
    return tokenizer->_token;
}

CFTypeRef CFStringTokenizerCopyCurrentTokenAttribute(CFStringTokenizerRef tokenizer, CFOptionFlags attribute) {
    // docs says this can validly return null, seems reasonable...
    return NULL;
}

/*
This requires linguistic databases for compound words.
CFIndex CFStringTokenizerGetCurrentSubTokens(CFStringTokenizerRef tokenizer, CFRange *ranges, CFIndex maxRangeLength, CFMutableArrayRef derivedSubTokens) {

}
*/
