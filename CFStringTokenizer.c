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
#include <unicode/ustring.h>

#define TYPE_MASK 0x000000FF

struct __CFStringTokenizer {
    CFRuntimeBase _base;
    CFStringRef _string;
    CFRange _range;
    CFOptionFlags _options;
    CFLocaleRef _locale;
    UBreakIterator *_break_itr;
    UChar *_text; // owned UTF-16 text; the break iterator keeps a pointer to it
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
}

CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index) {
    int32_t res = ubrk_following(tokenizer->_break_itr, index);
    if (res == UBRK_DONE) {
        return kCFStringTokenizerTokenNone;
    } else {
        return kCFStringTokenizerTokenNormal;
    }
}

CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer) {
    int32_t type = ubrk_next(tokenizer->_break_itr);
    return type == UBRK_DONE ? kCFStringTokenizerTokenNone : kCFStringTokenizerTokenNormal;
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer) {
    int32_t prev = ubrk_previous(tokenizer->_break_itr);
    int32_t curr = ubrk_next(tokenizer->_break_itr);
    if (curr == UBRK_DONE) {
        return CFRangeMake(0, -1);
    } else {
        return CFRangeMake(prev, curr - prev);
    }
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
