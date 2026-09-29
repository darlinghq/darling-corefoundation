# Nil dictionary subscripts

`dictionary-nil-subscript.m` exercises the public mutable-dictionary API. Build
it as an Objective-C executable linked to Foundation and run with the candidate
CoreFoundation library, not the system host Foundation alone.

The regression checks value replacement, removal through a nil subscript,
removal of an absent key, rejection of nil by ordinary `setObject:forKey:`, and
rejection of a nil subscript key. Success prints:

```
PASS: nil subscript removal, replacement and invalid-argument contracts
```

Apple documents nil subscript assignment as removal:
https://developer.apple.com/documentation/foundation/nsmutabledictionary/setobject%3Aforkeyedsubscript%3A

The existing implementation instead forwards nil to `setObject:forKey:` and
raises `NSInvalidArgumentException`. This also affects callers such as the X11
pasteboard when clearing a promised-data owner using dictionary subscripting.
