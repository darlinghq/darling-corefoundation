# NSArray and NSDictionary writeToURL:error:

`collections-write-to-url.m` writes an array and a dictionary with
`-writeToURL:error:`, reads them back, and checks the error contract: success
leaves `error` untouched, an unwritable location reports the real cause (not
`NSFileWriteUnknownError`; `ENOENT` as the error or as its underlying error), content that is not a property list reports
`NSPropertyListWriteInvalidError` (3852) without creating the file, and a NULL
error pointer is accepted. Build it as an Objective-C executable linked to
Foundation and CoreFoundation and run with the candidate CoreFoundation library.
Success prints:

```
PASS: writeToURL:error: for NSArray and NSDictionary reports the real error
```
