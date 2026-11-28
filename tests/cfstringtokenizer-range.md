# CFStringTokenizer ranges

Build `cfstringtokenizer-range.c` against CoreFoundation and run it under Darling.

`CFStringTokenizerCreate` documents its `range` as the range of characters in the string to tokenize. `CFStringTokenizerGetCurrentSubTokens` documents its returned ranges as relative to the string passed to `CFStringTokenizerCreate`, and `CFStringTokenizerGoToTokenAtIndex` takes an index into that string. The test therefore checks that a tokenizer created for a subrange returns token ranges in the original string, finds characters only inside that subrange, and reports no token outside it. It covers the word unit, `CFStringTokenizerSetString` with a new string and subrange, and the paragraph unit.

Installed baseline: both creation and `SetString` ignore the range, so the test tokenizes the whole string; the reported locations start at zero instead of the requested offset, and indices outside the requested range still find tokens. Candidate: zero failures.

## Provenance

Behavior is taken from the public `CFStringTokenizer` documentation (Apple Developer Documentation, `CFStringTokenizerCreate`, `CFStringTokenizerSetString`, `CFStringTokenizerGoToTokenAtIndex`, `CFStringTokenizerGetCurrentTokenRange`, and `CFStringTokenizerGetCurrentSubTokens`). No restricted material was used.
