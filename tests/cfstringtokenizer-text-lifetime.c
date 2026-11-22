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

// types may be NULL
static int collect_typed(CFStringTokenizerRef tok, CFRange *ranges, CFStringTokenizerTokenType *types)
{
	int n = 0;
	CFStringTokenizerTokenType t;
	while ((t = CFStringTokenizerAdvanceToNextToken(tok)) != kCFStringTokenizerTokenNone && n < MAX_TOKENS) {
		ranges[n] = CFStringTokenizerGetCurrentTokenRange(tok);
		if (types)
			types[n] = t;
		n++;
	}
	return n;
}

static int collect(CFStringTokenizerRef tok, CFRange *ranges)
{
	return collect_typed(tok, ranges, NULL);
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
	check("set string: first text has a first token", CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone);
	CFStringTokenizerSetString(tok, longer, CFRangeMake(0, CFStringGetLength(longer)));
	check("set string: no current token right after SetString",
	      CFStringTokenizerGetCurrentTokenRange(tok).location == kCFNotFound);
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

// Collects the tokens of a string for one tokenization unit.
static int tokenize(CFStringRef s, CFOptionFlags unit, CFRange *ranges)
{
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, s, CFRangeMake(0, CFStringGetLength(s)), unit, NULL);
	if (!tok)
		return -1;
	int n = collect(tok, ranges);
	CFRelease(tok);
	return n;
}

static int ranges_equal(const CFRange *got, int n, const CFRange *want, int wantCount)
{
	if (n != wantCount)
		return 0;
	for (int i = 0; i < n; i++)
		if (got[i].location != want[i].location || got[i].length != want[i].length)
			return 0;
	return 1;
}

static void test_paragraph_unit(void)
{
	CFRange got[MAX_TOKENS];

	// a paragraph is not a sentence: "A. B." is two sentences but one paragraph; the separator
	// belongs to the paragraph it ends
	const CFRange twoParagraphs[] = { {0, 6}, {6, 2} };
	int n = tokenize(CFSTR("A. B.\nC."), kCFStringTokenizerUnitParagraph, got);
	check("paragraph: \"A. B.\\nC.\" is two paragraphs", ranges_equal(got, n, twoParagraphs, 2));

	// CR LF is one separator, CR and LF alone are separators, an empty line is a paragraph
	const CFRange crlf[] = { {0, 3}, {3, 2}, {5, 2}, {7, 1}, {8, 1} };
	n = tokenize(CFSTR("a\r\nb\rc\n\nd"), kCFStringTokenizerUnitParagraph, got);
	check("paragraph: CR LF, CR and LF end a paragraph", ranges_equal(got, n, crlf, 5));

	// U+2029 ends a paragraph; U+0085 (NEL) and U+2028 (line separator) do not
	const UniChar ps[] = { 'a', 0x2029, 'b' };
	CFStringRef s = CFStringCreateWithCharacters(NULL, ps, 3);
	const CFRange psRanges[] = { {0, 2}, {2, 1} };
	n = tokenize(s, kCFStringTokenizerUnitParagraph, got);
	check("paragraph: U+2029 ends a paragraph", ranges_equal(got, n, psRanges, 2));
	CFRelease(s);

	const UniChar notSeparators[] = { 'a', 0x0085, 'b', 0x2028, 'c' };
	s = CFStringCreateWithCharacters(NULL, notSeparators, 5);
	const CFRange oneParagraph[] = { {0, 5} };
	n = tokenize(s, kCFStringTokenizerUnitParagraph, got);
	check("paragraph: NEL and U+2028 do not end a paragraph", ranges_equal(got, n, oneParagraph, 1));
	CFRelease(s);

	// no separator at all, the empty string, and a lone separator
	const CFRange whole[] = { {0, 3} };
	n = tokenize(CFSTR("abc"), kCFStringTokenizerUnitParagraph, got);
	check("paragraph: text without a separator is one paragraph", ranges_equal(got, n, whole, 1));
	n = tokenize(CFSTR(""), kCFStringTokenizerUnitParagraph, got);
	check("paragraph: empty string has no paragraph", n == 0);
	const CFRange lone[] = { {0, 1} };
	n = tokenize(CFSTR("\n"), kCFStringTokenizerUnitParagraph, got);
	check("paragraph: a lone separator is one paragraph", ranges_equal(got, n, lone, 1));

	// the text must stay alive here too, and SetString must keep the unit
	CFStringRef text = CFStringCreateWithCString(NULL, "A. B.\nC.", kCFStringEncodingASCII);
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
	                                                  kCFStringTokenizerUnitParagraph, NULL);
	check("paragraph: tokenizer created", tok != NULL);
	if (tok) {
		clobber_stack();
		n = collect(tok, got);
		check("paragraph: ranges unchanged after the stack was overwritten", ranges_equal(got, n, twoParagraphs, 2));
		CFStringRef other = CFSTR("x\ny\nz");
		CFStringTokenizerSetString(tok, other, CFRangeMake(0, CFStringGetLength(other)));
		const CFRange three[] = { {0, 2}, {2, 2}, {4, 1} };
		n = collect(tok, got);
		check("paragraph: SetString keeps the paragraph unit", ranges_equal(got, n, three, 3));
		CFRelease(tok);
	}
	CFRelease(text);
}

static void test_word_units_and_numbers(void)
{
	CFStringRef text = CFSTR("Hello, world 42!");
	CFRange got[MAX_TOKENS];
	CFStringTokenizerTokenType types[MAX_TOKENS];
	const CFStringTokenizerTokenType normal = kCFStringTokenizerTokenNormal;
	const CFStringTokenizerTokenType numeric = kCFStringTokenizerTokenNormal | kCFStringTokenizerTokenHasHasNumbersMask;

	// UnitWord returns the words only; white space and punctuation are not tokens
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
	                                                  kCFStringTokenizerUnitWord, NULL);
	check("word: tokenizer created", tok != NULL);
	if (tok) {
		const CFRange words[] = { {0, 5}, {7, 5}, {13, 2} };
		int n = collect_typed(tok, got, types);
		check("word: Hello, world, 42 and nothing else", ranges_equal(got, n, words, 3));
		check("word: numbers mask set for 42 only",
		      n == 3 && types[0] == normal && types[1] == normal && types[2] == numeric);
		check("word: no current token after the last one",
		      CFStringTokenizerGetCurrentTokenRange(tok).location == kCFNotFound);

		// go to a token: a word is found from any of its characters, a comma is not a token
		check("word: go to index 8 finds world", CFStringTokenizerGoToTokenAtIndex(tok, 8) == normal);
		CFRange r = CFStringTokenizerGetCurrentTokenRange(tok);
		check("word: index 8 is in {7, 5}", r.location == 7 && r.length == 5);
		check("word: advance after go to continues with 42", CFStringTokenizerAdvanceToNextToken(tok) == numeric);
		r = CFStringTokenizerGetCurrentTokenRange(tok);
		check("word: next token is {13, 2}", r.location == 13 && r.length == 2);
		check("word: go to index 14 finds 42 with the numbers mask", CFStringTokenizerGoToTokenAtIndex(tok, 14) == numeric);
		check("word: go to the comma finds no token", CFStringTokenizerGoToTokenAtIndex(tok, 5) == kCFStringTokenizerTokenNone);
		check("word: go past the end finds no token", CFStringTokenizerGoToTokenAtIndex(tok, 16) == kCFStringTokenizerTokenNone);
		CFRelease(tok);
	}

	// UnitWordBoundary keeps returning the separators between the words
	tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
	                              kCFStringTokenizerUnitWordBoundary, NULL);
	check("word boundary: tokenizer created", tok != NULL);
	if (tok) {
		const CFRange all[] = { {0, 5}, {5, 1}, {6, 1}, {7, 5}, {12, 1}, {13, 2}, {15, 1} };
		int n = collect_typed(tok, got, types);
		check("word boundary: words and separators", ranges_equal(got, n, all, 7));
		int numberMaskOnlyOn42 = n == 7;
		for (int i = 0; i < n; i++)
			numberMaskOnlyOn42 = numberMaskOnlyOn42 && types[i] == (i == 5 ? numeric : normal);
		check("word boundary: numbers mask set for 42 only", numberMaskOnlyOn42);
		check("word boundary: go to the comma finds it", CFStringTokenizerGoToTokenAtIndex(tok, 5) == normal);
		CFRelease(tok);
	}

	// the number status of a word break iterator means nothing for the other units
	CFStringRef two = CFSTR("Room 42.\nNext.");
	CFOptionFlags others[] = { kCFStringTokenizerUnitSentence, kCFStringTokenizerUnitParagraph, kCFStringTokenizerUnitLineBreak };
	for (int u = 0; u < 3; u++) {
		tok = CFStringTokenizerCreate(NULL, two, CFRangeMake(0, CFStringGetLength(two)), others[u], NULL);
		int n = tok ? collect_typed(tok, got, types) : -1;
		int allNormal = n > 0;
		for (int i = 0; i < n; i++)
			allNormal = allNormal && types[i] == normal;
		check("other units: tokens are plain normal tokens", allNormal);
		if (tok)
			CFRelease(tok);
	}
}

// The type of the only token of a one-token string.
static CFStringTokenizerTokenType only_token_type(CFStringRef s, CFOptionFlags unit)
{
	CFRange got[MAX_TOKENS];
	CFStringTokenizerTokenType types[MAX_TOKENS];
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, s, CFRangeMake(0, CFStringGetLength(s)), unit, NULL);
	if (!tok)
		return kCFStringTokenizerTokenNone;
	int n = collect_typed(tok, got, types);
	CFRelease(tok);
	return n == 1 && got[0].location == 0 && got[0].length == CFStringGetLength(s) ? types[0] : kCFStringTokenizerTokenNone;
}

static void test_number_mask_follows_content(void)
{
	const CFStringTokenizerTokenType normal = kCFStringTokenizerTokenNormal;
	const CFStringTokenizerTokenType numeric = kCFStringTokenizerTokenNormal | kCFStringTokenizerTokenHasHasNumbersMask;
	CFOptionFlags units[] = { kCFStringTokenizerUnitWord, kCFStringTokenizerUnitWordBoundary };

	// the mask says the token contains a number, wherever the digits are
	const UniChar arabicIndic[] = { 'a', 0x0663 };
	CFStringRef nonAscii = CFStringCreateWithCharacters(NULL, arabicIndic, 2);
	for (int u = 0; u < 2; u++) {
		check("mask: 42abc has the numbers mask", only_token_type(CFSTR("42abc"), units[u]) == numeric);
		check("mask: ab42 has the numbers mask", only_token_type(CFSTR("ab42"), units[u]) == numeric);
		check("mask: 3.14 has the numbers mask", only_token_type(CFSTR("3.14"), units[u]) == numeric);
		check("mask: a non-ASCII digit (U+0663) has the numbers mask", only_token_type(nonAscii, units[u]) == numeric);
		check("mask: world has no numbers mask", only_token_type(CFSTR("world"), units[u]) == normal);
	}
	CFRelease(nonAscii);
}

static void test_go_to_negative_index(void)
{
	CFStringRef text = CFSTR("Hello, world");
	CFStringTokenizerRef tok = CFStringTokenizerCreate(NULL, text, CFRangeMake(0, CFStringGetLength(text)),
	                                                  kCFStringTokenizerUnitWord, NULL);
	check("negative index: tokenizer created", tok != NULL);
	if (!tok)
		return;
	check("negative index: go to -1 finds no token", CFStringTokenizerGoToTokenAtIndex(tok, -1) == kCFStringTokenizerTokenNone);
	check("negative index: no current token", CFStringTokenizerGetCurrentTokenRange(tok).location == kCFNotFound);
	check("negative index: advance still starts at the first word", CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone);
	CFRange r = CFStringTokenizerGetCurrentTokenRange(tok);
	check("negative index: first word is {0, 5}", r.location == 0 && r.length == 5);
	CFRelease(tok);
}

int main(void)
{
	test_short_text_outlives_create();
	test_long_text_outlives_create();
	test_set_string();
	test_empty_and_single_character();
	test_paragraph_unit();
	test_word_units_and_numbers();
	test_number_mask_follows_content();
	test_go_to_negative_index();

	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
