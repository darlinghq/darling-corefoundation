# XML property list with a UTF-8 byte order mark

`plist-xml-bom.c` parses a BOM-prefixed XML plist whose bytes end exactly at an inaccessible page. The parser's end pointer used to be computed from the buffer after the BOM was skipped, so it could look three bytes past the data and fault (or, if the bytes were readable, read them); after the fix the plist parses. It prints `1/1 passed`.

Whether the unfixed parser actually touches the bytes past the end depends on how it scans after `</plist>`, so this test may pass before the fix; it is the regression test for the corrected bound, not a guaranteed reproducer.
