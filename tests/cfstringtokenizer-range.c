// CFStringTokenizer must tokenize only the requested CFRange and return token ranges relative to
// the original string, as documented by CFStringTokenizerCreate and CFStringTokenizerSetString.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int failures;

static void check(const char *label, int ok)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", label);
	failures += !ok;
}

static CFRange first_token(CFStringTokenizerRef tokenizer)
{
	CFRange invalid = { kCFNotFound, 0 };
	if (CFStringTokenizerAdvanceToNextToken(tokenizer) == kCFStringTokenizerTokenNone)
		return invalid;
	return CFStringTokenizerGetCurrentTokenRange(tokenizer);
}

static int range_is(CFRange range, CFIndex location, CFIndex length)
{
	return range.location == location && range.length == length;
}

static void test_create_range(void)
{
	CFStringRef text = CFSTR("prefix hello world suffix");
	CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, text, CFRangeMake(7, 5),
	                                                        kCFStringTokenizerUnitWord, NULL);
	check("create: tokenizer created", tokenizer != NULL);
	if (!tokenizer) {
		return;
	}

	CFRange token = first_token(tokenizer);
	check("create: first token is the requested substring", range_is(token, 7, 5));
	check("create: no token outside the requested range",
	      CFStringTokenizerAdvanceToNextToken(tokenizer) == kCFStringTokenizerTokenNone);

	CFStringTokenizerTokenType type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 9);
	check("create: go to a character inside the range finds the token", type != kCFStringTokenizerTokenNone);
	token = CFStringTokenizerGetCurrentTokenRange(tokenizer);
	check("create: go to reports the range in the original string", range_is(token, 7, 5));

	type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0);
	check("create: go before the range finds no token", type == kCFStringTokenizerTokenNone);
	type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 12);
	check("create: go after the range finds no token", type == kCFStringTokenizerTokenNone);

	CFRelease(tokenizer);
}

static void test_set_string_range(void)
{
	CFStringRef initial = CFSTR("aaaa bbbb");
	CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, initial, CFRangeMake(0, 9),
	                                                         kCFStringTokenizerUnitWord, NULL);
	check("set string: tokenizer created", tokenizer != NULL);
	if (!tokenizer) {
		return;
	}

	CFStringRef replacement = CFSTR("xx alpha beta yy");
	CFStringTokenizerSetString(tokenizer, replacement, CFRangeMake(3, 5));
	CFRange token = first_token(tokenizer);
	check("set string: first token is the requested substring", range_is(token, 3, 5));
	check("set string: no token outside the requested range",
	      CFStringTokenizerAdvanceToNextToken(tokenizer) == kCFStringTokenizerTokenNone);

	CFStringTokenizerTokenType type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 7);
	check("set string: go to a character inside the range finds the token", type != kCFStringTokenizerTokenNone);
	token = CFStringTokenizerGetCurrentTokenRange(tokenizer);
	check("set string: go to reports the range in the replacement string", range_is(token, 3, 5));

	CFRelease(tokenizer);
}

static void test_paragraph_range(void)
{
	CFStringRef text = CFSTR("skip\nkeep\nskip");
	CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, text, CFRangeMake(5, 5),
	                                                         kCFStringTokenizerUnitParagraph, NULL);
	check("paragraph: tokenizer created", tokenizer != NULL);
	if (!tokenizer) {
		return;
	}

	CFRange token = first_token(tokenizer);
	check("paragraph: only the paragraph in the range is returned", range_is(token, 5, 5));
	CFRelease(tokenizer);
}

int main(void)
{
	test_create_range();
	test_set_string_range();
	test_paragraph_range();
	printf("%s\n", failures ? "FAILED" : "ALL PASSED");
	return failures ? 1 : 0;
}
