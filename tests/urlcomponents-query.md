# CFURLComponents query items

`urlcomponents-query.c` parses a URL with repeated, percent-encoded, empty and
valueless query items through the `_CFURLComponents*` functions, checks order
and decoding, the type ID, and that an empty or NULL query yields an empty
array or NULL. It prints `PASS` on success. Before the backend is built into
CoreFoundation the program does not link.
