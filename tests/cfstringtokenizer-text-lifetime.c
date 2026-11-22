// CFStringTokenizer: the tokenizer must keep its own copy of the text alive for as long as it
// tokenizes (the ICU break iterator it is built on keeps a pointer to the text instead of copying it).
//
// Every token range below is checked after the stack and the heap were overwritten with a pattern,
// so a tokenizer that still reads a dead stack buffer or a freed heap buffer returns other ranges.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void check(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

// Fills the stack below the caller with UTF-16 'z' characters.
static void __attribute__((noinline)) clobber_stack(void)
{
	volatile unsigned char pad[64 * 1024];
	for (size_t i = 0; i < sizeof pad; i++)
		pad[i] = (i & 1) ? 0x00 : 'z';
}

#define CLOBBER_SIZES 5
#define CLOBBER_PER_SIZE 16
#define CLOBBER_BLOCKS (CLOBBER_SIZES * CLOBBER_PER_SIZE)
static void *clobber_blocks[CLOBBER_BLOCKS];

// Allocates blocks of the given size, and of the four neighbouring 16-byte sizes in case the
// allocator rounds sizes up, filled with UTF-16 'z' characters, so a block that was just freed is
// likely handed out again and overwritten. This cannot be guaranteed for every malloc; the
// stack overwrite above is the deterministic part. The blocks are kept until release_heap().
static void clobber_heap(size_t bytes)
{
	for (int i = 0; i < CLOBBER_BLOCKS; i++) {
		size_t size = bytes + 16 * (size_t)(i % CLOBBER_SIZES) - 32;
		unsigned char *p = malloc(size);
		for (size_t j = 0; j < size; j++)
			p[j] = (j & 1) ? 0x00 : 'z';
		clobber_blocks[i] = p;
	}
}

static void release_heap(void)
{
	for (int i = 0; i < CLOBBER_BLOCKS; i++) {
		free(clobber_blocks[i]);
		clobber_blocks[i] = NULL;
	}
}

// "word word word ..." with the given number of repetitions (5 characters each).
static CFStringRef make_words(int repetitions)
{
	CFMutableStringRef s = CFStringCreateMutable(NULL, 0);
	for (int i = 0; i < repetitions; i++)
		CFStringAppend(s, CFSTR("word "));
	return s;
}

#define MAX_TOKENS 1024

static int collect(CFStringTokenizerRef tok, CFRange *ranges)
{
	int n = 0;
	while (CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone && n < MAX_TOKENS) {
		ranges[n] = CFStringTokenizerGetCurrentTokenRange(tok);
		n++;
	}
	return n;
}

// WordBoundary returns every word and every space between words, in order.
static int is_word_boundary_sequence(const CFRange *ranges, int n, int repetitions)
{
	if (n != repetitions * 2)
		return 0;
	for (int i = 0; i < repetitions; i++) {
		if (ranges[2 * i].location != 5 * i || ranges[2 * i].length != 4)
			return 0;
		if (ranges[2 * i + 1].location != 5 * i + 4 || ranges[2 * i + 1].length != 1)
			return 0;
	}
	return 1;
}

static void test_short_text_outlives_create(void)
{
	// 6 repetitions: 30 characters, far below the size of the old on-stack copy
	CFStringRef s = make_words(6);
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, s, CFRangeMake(0, CFStringGetLength(s)),
	                                                  kCFStringTokenizerUnitWordBoundary, NULL);
	check("short: tokenizer created", tok != NULL);
	if (!tok) {
		CFRelease(s);
		return;
	}
	clobber_stack();
	CFRange ranges[MAX_TOKENS];
	int n = collect(tok, ranges);
	check("short: ranges unchanged after the stack was overwritten", is_word_boundary_sequence(ranges, n, 6));
	CFRelease(tok);
	CFRelease(s);
}

static void test_long_text_outlives_create(void)
{
	// 400 repetitions: 2000 characters, above the 768 characters the old code kept on the stack
	CFStringRef s = make_words(400);
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, s, CFRangeMake(0, CFStringGetLength(s)),
	                                                  kCFStringTokenizerUnitWordBoundary, NULL);
	check("long: tokenizer created", tok != NULL);
	if (!tok) {
		CFRelease(s);
		return;
	}
	clobber_stack();
	clobber_heap((size_t)CFStringGetLength(s) * sizeof(UniChar));
	CFRange ranges[MAX_TOKENS];
	int n = collect(tok, ranges);
	check("long: ranges unchanged after the freed heap block was reused", is_word_boundary_sequence(ranges, n, 400));
	release_heap();
	CFRelease(tok);
	CFRelease(s);
}

static void test_set_string(void)
{
	CFStringRef first = make_words(2);
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, first, CFRangeMake(0, CFStringGetLength(first)),
	                                                  kCFStringTokenizerUnitWordBoundary, NULL);
	check("set string: tokenizer created", tok != NULL);
	if (!tok) {
		CFRelease(first);
		return;
	}
	CFRange ranges[MAX_TOKENS];

	// replace the text with a long one: the new text must stay alive after SetString returns
	CFStringRef longer = make_words(400);
	CFStringTokenizerSetString(tok, longer, CFRangeMake(0, CFStringGetLength(longer)));
	clobber_stack();
	clobber_heap((size_t)CFStringGetLength(longer) * sizeof(UniChar));
	int n = collect(tok, ranges);
	check("set string: long replacement tokenized after the stack and heap were overwritten",
	      is_word_boundary_sequence(ranges, n, 400));
	release_heap();

	// and with a short one: the long text is freed, the short one must be tokenized from its start
	CFStringRef shorter = make_words(3);
	CFStringTokenizerSetString(tok, shorter, CFRangeMake(0, CFStringGetLength(shorter)));
	clobber_stack();
	clobber_heap((size_t)CFStringGetLength(longer) * sizeof(UniChar));
	n = collect(tok, ranges);
	check("set string: short replacement tokenized from its start", is_word_boundary_sequence(ranges, n, 3));
	release_heap();

	CFRelease(tok);
	CFRelease(first);
	CFRelease(longer);
	CFRelease(shorter);
}

static void test_empty_and_single_character(void)
{
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, CFSTR(""), CFRangeMake(0, 0),
	                                                  kCFStringTokenizerUnitWordBoundary, NULL);
	check("empty: tokenizer created", tok != NULL);
	if (tok) {
		check("empty: no token", CFStringTokenizerAdvanceToNextToken(tok) == kCFStringTokenizerTokenNone);
		CFRelease(tok);
	}

	tok = CFStringTokenizerCreate(NULL, CFSTR("a"), CFRangeMake(0, 1), kCFStringTokenizerUnitWordBoundary, NULL);
	check("one character: tokenizer created", tok != NULL);
	if (tok) {
		clobber_stack();
		CFRange r;
		check("one character: one token", CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone);
		r = CFStringTokenizerGetCurrentTokenRange(tok);
		check("one character: range is (0, 1)", r.location == 0 && r.length == 1);
		check("one character: no second token", CFStringTokenizerAdvanceToNextToken(tok) == kCFStringTokenizerTokenNone);
		CFRelease(tok);
	}
}

int main(void)
{
	test_short_text_outlives_create();
	test_long_text_outlives_create();
	test_set_string();
	test_empty_and_single_character();

	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
