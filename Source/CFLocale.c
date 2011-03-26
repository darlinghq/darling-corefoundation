/* CFLocale.c
   
   Copyright (C) 2011 Free Software Foundation, Inc.
   
   Written by: Stefan Bidigaray
   Date: March, 2011
   
   This file is part of the GNUstep CoreBase Library.
   
   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#include "CoreFoundation/CFLocale.h"

#include "CoreFoundation/CFBase.h"
#include "CoreFoundation/CFString.h"
#include "CoreFoundation/CFRuntime.h"

#include <pthread.h>
#include <unicode/uloc.h>
#include <unicode/ulocdata.h>

#define BUFFER_SIZE 1024

struct __CFLocale
{
  /* The ivar order is important... must be exactly like NSLocale's. */
  CFRuntimeBase          _parent;
  CFStringRef            _identifier;
  CFMutableDictionaryRef _components;
  pthread_spinlock_t     _lock;
};

/* Use a spin lock because it's faster than a mutex.  Just make sure to not
   keep it locked for very long. */
static pthread_spinlock_t _kCFLocaleLock;

static CFTypeID _kCFLocaleTypeID;
static CFLocaleRef _kCFLocaleCurrent = NULL;
static CFLocaleRef _kCFLocaleSystem = NULL;
static CFArrayRef _kCFLocaleAvailableLocaleIdentifiers = NULL;
static CFArrayRef _kCFLocaleISOCountryCodes = NULL;
static CFArrayRef _kCFLocaleISOLanguageCodes = NULL;

static const CFRuntimeClass CFLocaleClass =
{
  0,
  "CFLocale",
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
};

void CFLocaleInitialize (void)
{
  pthread_spin_init (&_kCFLocaleLock, PTHREAD_PROCESS_SHARED);
  _kCFLocaleTypeID = _CFRuntimeRegisterClass(&CFLocaleClass);
}

static CFLocaleLanguageDirection
ICUToCFLocaleOrientation (ULayoutType layout)
{
  switch (layout)
    {
      case ULOC_LAYOUT_LTR:
        return kCFLocaleLanguageDirectionLeftToRight;
      case ULOC_LAYOUT_RTL:
        return kCFLocaleLanguageDirectionRightToLeft;
      case ULOC_LAYOUT_TTB:
        return kCFLocaleLanguageDirectionTopToBottom;
      case ULOC_LAYOUT_BTT:
        return kCFLocaleLanguageDirectionBottomToTop;
      default:
        return kCFLocaleLanguageDirectionUnknown;
    }
}



CFLocaleRef
CFLocaleCopyCurrent (void)
{
  CFLocaleRef result;
  
  pthread_spin_lock (&_kCFLocaleLock);
  if (_kCFLocaleCurrent)
    {
      result = (CFLocaleRef)CFRetain ((CFTypeRef)_kCFLocaleCurrent);
      pthread_spin_unlock (&_kCFLocaleLock);
      return result;
    }
  pthread_spin_unlock (&_kCFLocaleLock);
  
  result = CFLocaleCreate (kCFAllocatorSystemDefault, NULL);
  
  pthread_spin_lock (&_kCFLocaleLock);
  _kCFLocaleCurrent = (CFLocaleRef)CFRetain ((CFTypeRef)result);
  pthread_spin_unlock (&_kCFLocaleLock);
  return result;
}

CFLocaleRef
CFLocaleCreate (CFAllocatorRef allocator,
                CFStringRef localeIdent)
{
  struct __CFLocale *new;
  
  new = (struct __CFLocale *)_CFRuntimeCreateInstance (allocator,
    CFLocaleGetTypeID(),
    sizeof(struct __CFLocale) - sizeof(CFRuntimeBase),
    NULL);
  
  new->_identifier =
    CFLocaleCreateCanonicalLocaleIdentifierFromString (allocator, localeIdent);
  new->_components = CFDictionaryCreateMutable (allocator,
    0,
    &kCFTypeDictionaryKeyCallBacks,
    &kCFTypeDictionaryValueCallBacks);
  pthread_spin_init (&(new->_lock), PTHREAD_PROCESS_SHARED);
  
  return new;
}

CFLocaleRef
CFLocaleCreateCopy (CFAllocatorRef allocator,
                    CFLocaleRef locale)
{
  return (CFLocaleRef)CFRetain((CFTypeRef)locale);
}

CFLocaleRef
CFLocaleGetSystem (void)
{
  CFLocaleRef result;
  pthread_spin_lock (&_kCFLocaleLock);
  if (_kCFLocaleSystem)
    {
      result = (CFLocaleRef)CFRetain ((CFTypeRef)_kCFLocaleSystem);
      pthread_spin_unlock (&_kCFLocaleLock);
      return result;
    }
  pthread_spin_unlock (&_kCFLocaleLock);
  
  result = CFLocaleCreate (kCFAllocatorSystemDefault, CFSTR(""));
  
  pthread_spin_lock (&_kCFLocaleLock);
  // Double check system locale wasn't already set.
  if (_kCFLocaleSystem)
    {
      result = (CFLocaleRef)CFRetain ((CFTypeRef)_kCFLocaleSystem);
      pthread_spin_unlock (&_kCFLocaleLock);
      return result;
    }
  _kCFLocaleSystem = (CFLocaleRef)CFRetain ((CFTypeRef)result);
  pthread_spin_unlock (&_kCFLocaleLock);
  return result;
}

CFArrayRef
CFLocaleCopyAvailableLocaleIdentifiers (void)
{
  int32_t count;
  int32_t idx;
  CFMutableArrayRef mArray;
  
  pthread_spin_lock (&_kCFLocaleLock);
  if (_kCFLocaleAvailableLocaleIdentifiers)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      return (CFArrayRef)CFRetain (_kCFLocaleAvailableLocaleIdentifiers);
    }
  pthread_spin_unlock (&_kCFLocaleLock);
  
  count = uloc_countAvailable ();
  mArray = CFArrayCreateMutable (kCFAllocatorSystemDefault,
    0,
    &kCFTypeArrayCallBacks);
  idx = 0;
  while (count > idx)
    {
      const char *str = uloc_getAvailable (idx);
      CFStringRef cfStr = CFStringCreateWithCString (kCFAllocatorSystemDefault,
        str, CFStringGetSystemEncoding());
      CFArrayAppendValue (mArray, cfStr);
      CFRelease ((CFTypeRef)cfStr);
      ++idx;
    }
  
  pthread_spin_lock (&_kCFLocaleLock);
  // Double check
  if (_kCFLocaleAvailableLocaleIdentifiers)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      CFRelease (mArray);
      return (CFArrayRef)CFRetain (_kCFLocaleAvailableLocaleIdentifiers);
    }
  _kCFLocaleAvailableLocaleIdentifiers =
    CFArrayCreateCopy (kCFAllocatorSystemDefault, mArray);
  pthread_spin_unlock (&_kCFLocaleLock);
  CFRelease (mArray);
  return (CFArrayRef)CFRetain (_kCFLocaleAvailableLocaleIdentifiers);
}

CFArrayRef
CFLocaleCopyISOCountryCodes (void)
{
  const char *const *cCodes;
  CFMutableArrayRef mArray;
  int idx;
  
  pthread_spin_lock (&_kCFLocaleLock);
  if (_kCFLocaleISOCountryCodes)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      return (CFArrayRef)CFRetain (_kCFLocaleISOCountryCodes);
    }
  pthread_spin_unlock (&_kCFLocaleLock);
  
  cCodes = uloc_getISOCountries ();
  mArray = CFArrayCreateMutable (kCFAllocatorSystemDefault,
    0,
    &kCFTypeArrayCallBacks);
  for (idx = 0 ; cCodes[idx] ; ++idx)
    {
      CFStringRef cfStr = CFStringCreateWithCString (kCFAllocatorSystemDefault,
        cCodes[idx], CFStringGetSystemEncoding());
      CFArrayAppendValue (mArray, cfStr);
      CFRelease ((CFTypeRef)cfStr);
    }
  
  pthread_spin_lock (&_kCFLocaleLock);
  // Double check that value hasn't been set
  if (_kCFLocaleISOCountryCodes)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      CFRelease (mArray);
      return (CFArrayRef)CFRetain (_kCFLocaleISOCountryCodes);
    }
  _kCFLocaleISOCountryCodes =
    CFArrayCreateCopy (kCFAllocatorSystemDefault, mArray);
  pthread_spin_unlock (&_kCFLocaleLock);
  
  CFRelease (mArray);
  
  return (CFArrayRef)CFRetain (_kCFLocaleISOCountryCodes);
}

CFArrayRef
CFLocaleCopyISOLanguageCodes (void)
{
  const char *const *cCodes;
  CFMutableArrayRef mArray;
  int idx;
  
  pthread_spin_lock (&_kCFLocaleLock);
  if (_kCFLocaleISOLanguageCodes)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      return (CFArrayRef)CFRetain (_kCFLocaleISOLanguageCodes);
    }
  pthread_spin_unlock (&_kCFLocaleLock);
  
  cCodes = uloc_getISOLanguages ();
  mArray = CFArrayCreateMutable (kCFAllocatorSystemDefault,
    0,
    &kCFTypeArrayCallBacks);
  for (idx = 0 ; cCodes[idx] != NULL ; ++idx)
    {
      CFStringRef cfStr = CFStringCreateWithCString (kCFAllocatorSystemDefault,
        cCodes[idx], CFStringGetSystemEncoding());
      CFArrayAppendValue (mArray, cfStr);
      CFRelease ((CFTypeRef)cfStr);
    }
  
  pthread_spin_lock (&_kCFLocaleLock);
  // Double check that value hasn't been set
  if (_kCFLocaleISOLanguageCodes)
    {
      pthread_spin_unlock (&_kCFLocaleLock);
      return (CFArrayRef)CFRetain (_kCFLocaleISOLanguageCodes);
    }
  _kCFLocaleISOLanguageCodes =
    CFArrayCreateCopy (kCFAllocatorSystemDefault, mArray);
  pthread_spin_unlock (&_kCFLocaleLock);
  
  CFRelease (mArray);
  
  return (CFArrayRef)CFRetain (_kCFLocaleISOLanguageCodes);
}

CFArrayRef
CFLocaleCopyISOCurrencyCodes (void);

CFArrayRef
CFLocaleCopyCommonISOCurrencyCodes (void);

CFArrayRef
CFLocaleCopyPreferredLanguages (void);

CFStringRef
CFLocaleCopyDisplayNameForPropertyValue (CFLocaleRef displayLocale,
                                         CFStringRef key,
                                         CFStringRef value)
{
/* FIXME  char kw[ULOC_KEYWORDS_CAPACITY];
  UniChar buffer[BUFFER_SIZE];
  UErrorCode err = U_ZERO_ERROR;
  
  if (CFStringGetCString (key, buffer, BUFFER_SIZE-1, CFStringGetSystemEncoding())
      && CFStringGetCString ()
  
  length = uloc_getDisplayKeywordValue (cLocale, kw, dLocale, buffer,
    BUFFER_SIZE, &err);
  if (U_FAILURE(err) && err != U_BUFFER_OVERFLOW_ERROR)
    return NULL;
  if (length > BUFFER_SIZE)
    length = BUFFER_SIZE;
  
  return CFStringCreateWithCharacters (NULL, buffer, length);*/
  return NULL;
}

CFTypeRef
CFLocaleGetValue (CFLocaleRef locale,
                  CFStringRef key)
{
// FIXME: this is terribly broken
  CFTypeRef result;
  char cLocale[ULOC_FULLNAME_CAPACITY];
  char buffer[BUFFER_SIZE];
  int32_t length = 0;
  UErrorCode err = U_ZERO_ERROR;
  
  // Don't waste any time.
  if (locale == NULL || key == NULL)
    return NULL;
  if (key == kCFLocaleIdentifier)
    return (CFTypeRef)locale->_identifier;
  
  // Make sure we haven't been through this already.
  pthread_spin_lock (&(((struct __CFLocale*)locale)->_lock));
  if (CFDictionaryGetValueIfPresent(locale->_components, key,
      (const void **)&result))
    {
      pthread_spin_unlock (&(((struct __CFLocale*)locale)->_lock));
      return result;
    }
  pthread_spin_unlock (&(((struct __CFLocale*)locale)->_lock));
  
  if (!CFStringGetCString (locale->_identifier, cLocale,
      ULOC_FULLNAME_CAPACITY, CFStringGetSystemEncoding()))
    return NULL;
  
  if (key == kCFLocaleMeasurementSystem
      || key == kCFLocaleUsesMetricSystem)
    {
      UMeasurementSystem ums= ulocdata_getMeasurementSystem (cLocale, &err);
      if (key == kCFLocaleMeasurementSystem)
        {
          if (ums == UMS_SI)
            return (CFTypeRef)CFSTR("Metric");
          else
            result = (CFTypeRef)CFSTR("U.S.");
        }
      else
        {
          // FIXME: requires CFBoolean
          return NULL;
        }
    }
  else if (key == kCFLocaleDecimalSeparator)
    {
      // FIXME: CFNumberFormatter
      return NULL;
    }
  else if (key == kCFLocaleGroupingSeparator)
    {
      // FIXME: CFNumberFormatter
      return NULL;
    }
  else if (key == kCFLocaleCurrencySymbol)
    {
      // FIXME: CFNumberFormatter
      return NULL;
    }
  else if (key == kCFLocaleCurrencyCode)
    {
      // FIXME: CFNumberFormatter
      length =
        uloc_getKeywordValue (cLocale, "currency", buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleLanguageCode)
    {
      length = uloc_getLanguage (cLocale, buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleCountryCode)
    {
      length = uloc_getCountry (cLocale, buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleScriptCode)
    {
      length = uloc_getScript (cLocale, buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleVariantCode)
    {
      length = uloc_getVariant (cLocale, buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleExemplarCharacterSet)
    {
      return kCFNull;
    }
  else if (key == kCFLocaleCalendarIdentifier)
    {
      length =
        uloc_getKeywordValue (cLocale, "calendar", buffer, BUFFER_SIZE, &err);
      if (strncmp(buffer, "gregorian", sizeof("gregorian")-1))
        result = (CFTypeRef)kCFGregorianCalendar;
    }
  else if (key == kCFLocaleCalendar)
    {
      return kCFNull;
    }
  else if (key == kCFLocaleCollationIdentifier)
    {
      length =
        uloc_getKeywordValue (cLocale, "collation", buffer, BUFFER_SIZE, &err);
    }
  else if (key == kCFLocaleCollatorIdentifier)
    {
      return kCFNull;
    }
  else if (key == kCFLocaleQuotationBeginDelimiterKey)
    {
      UniChar ubuffer[BUFFER_SIZE];
      ULocaleData *uld = ulocdata_open (cLocale, &err);
      length = ulocdata_getDelimiter (uld, ULOCDATA_QUOTATION_START,
        ubuffer, BUFFER_SIZE, &err);
      
    }
  else if (key == kCFLocaleQuotationEndDelimiterKey)
    {
      return kCFNull;
    }
  else if (key == kCFLocaleAlternateQuotationBeginDelimiterKey)
    {
      return kCFNull;
    }
  else if (key == kCFLocaleAlternateQuotationEndDelimiterKey)
    {
      return kCFNull;
    }
  else
    {
      return kCFNull;
    }
  
  if (U_FAILURE(err) || length == 0)
    result = kCFNull;
  else
    {
      result = (CFTypeRef)
        CFStringCreateWithCString (NULL, buffer, CFStringGetSystemEncoding());
      if (result == NULL)
        result = kCFNull;
    }
  
  pthread_spin_lock (&(((struct __CFLocale*)locale)->_lock));
  CFDictionaryAddValue (locale->_components, key, result);
  pthread_spin_unlock (&(((struct __CFLocale*)locale)->_lock));
  
  return result;
}

CFStringRef
CFLocaleGetIdentifier (CFLocaleRef locale)
{
  return locale->_identifier;
}

CFStringRef
CFLocaleCreateCanonicalLocaleIdentifierFromString (CFAllocatorRef allocator,
                                                   CFStringRef localeIdent)
{
  CFStringRef result;
  char cLocale[ULOC_FULLNAME_CAPACITY];
  char buffer[ULOC_FULLNAME_CAPACITY];
  UErrorCode err = U_ZERO_ERROR;
  
  if (!CFStringGetCString(localeIdent, cLocale, ULOC_FULLNAME_CAPACITY,
         CFStringGetSystemEncoding()))
    return NULL;
  
  uloc_canonicalize (cLocale, buffer, ULOC_FULLNAME_CAPACITY, &err);
  if (U_FAILURE(err))
    return NULL;
  
  result =
    CFStringCreateWithCString (allocator, buffer, CFStringGetSystemEncoding());
  
  return result;
}

CFStringRef
CFLocaleCreateCanonicalLanguageIdentifierFromString (CFAllocatorRef allocator,
                                                     CFStringRef localeIdent)
{
  CFStringRef result;
  char cLocale[ULOC_FULLNAME_CAPACITY];
  char canonical[ULOC_FULLNAME_CAPACITY];
  char lang[ULOC_LANG_CAPACITY];
  UErrorCode err = U_ZERO_ERROR;
  
  if (!CFStringGetCString(localeIdent, cLocale, ULOC_FULLNAME_CAPACITY,
         CFStringGetSystemEncoding()))
    return NULL;
  
  uloc_canonicalize (cLocale, canonical, BUFFER_SIZE, &err);
  uloc_getLanguage (canonical, lang, ULOC_LANG_CAPACITY, &err);
  if (U_FAILURE(err))
    return NULL;
  
  result =
    CFStringCreateWithCString (allocator, lang, CFStringGetSystemEncoding());
  
  return result;
}

#define ADD_KEY_VALUE_TO_DICTIONARY(dictionary, key, value, length, error) do \
{ \
  if (U_SUCCESS(error) && length > 0) \
    { \
      CFStringRef value__ = CFStringCreateWithCString (NULL, value, \
        CFStringGetSystemEncoding()); \
      CFDictionaryAddValue (dictionary, key, value__); \
      CFRelease ((CFTypeRef)value__); \
    } \
  error = U_ZERO_ERROR; \
} while (0)

CFDictionaryRef
CFLocaleCreateComponentsFromLocaleIdentifier (CFAllocatorRef allocator,
                                              CFStringRef localeIdent)
{
  char locale[ULOC_FULLNAME_CAPACITY];
  char buffer[ULOC_KEYWORDS_CAPACITY];
  CFDictionaryRef result;
  CFMutableDictionaryRef dict;
  int32_t len;
  UErrorCode err = U_ZERO_ERROR;
  
  if (!CFStringGetCString (localeIdent, locale, ULOC_FULLNAME_CAPACITY,
      CFStringGetSystemEncoding()))
    return NULL;
  
  /* Using capacity = 7 because that's the most amount of keys we'll have:
      language_script_country_variant@calendar;collation;currency.
  */
  dict = CFDictionaryCreateMutable (NULL, 7,
    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  
  len = uloc_getLanguage (locale, buffer, ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleLanguageCode, buffer, len, err);

  len = uloc_getCountry (locale, buffer, ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleCountryCode, buffer, len, err);

  len = uloc_getScript (locale, buffer, ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleScriptCode, buffer, len, err);

  len = uloc_getVariant (locale, buffer, ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleVariantCode, buffer, len, err);
  
  len = uloc_getKeywordValue (locale, "calendar", buffer,
    ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleCalendarIdentifier, buffer, len,
    err);
  
  len = uloc_getKeywordValue (locale, "collation", buffer,
    ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleCollationIdentifier, buffer, len,
    err);
  
  len = uloc_getKeywordValue (locale, "currency", buffer,
    ULOC_KEYWORDS_CAPACITY, &err);
  ADD_KEY_VALUE_TO_DICTIONARY(dict, kCFLocaleCurrencyCode, buffer, len, err);
  
  result = CFDictionaryCreateCopy (allocator, (CFDictionaryRef)dict);
  CFRelease(dict);
  return result;
}

CFStringRef
CFLocaleCreateLocaleIdentifierFromComponents (CFAllocatorRef allocator,
                                              CFDictionaryRef dictionary)
{
  /* A locale identifier only includes a few of the keys provided
     by CFLocale.  According to UTS #35 (http://unicode.org/reports/tr35/tr35-6.html)
     locales have the following format:
        locale_id      := base_locale_id options?
        base_locale_id := extended_RFC3066bis_identifiers
        options        := "@" key "=" type ("," key "=" type )*
    Keep in mind, however, that ICU's key separator is ";".  This shouldn't
    be a problem as long as we use ULOC_KEYWORD_ITEM_SEPARATOR (and friends).
  */
  char locale[ULOC_FULLNAME_CAPACITY];
  char lang[ULOC_LANG_CAPACITY];
  char country[ULOC_COUNTRY_CAPACITY];
  char script[ULOC_SCRIPT_CAPACITY];
  char variant[ULOC_KEYWORDS_CAPACITY]; // use this for lack of a better one
  char keyword[ULOC_KEYWORD_AND_VALUES_CAPACITY];
  Boolean hasCountry;
  Boolean hasScript;
  Boolean hasVariant;
  UErrorCode err = U_ZERO_ERROR;
  CFStringRef value;
  
  if (dictionary == NULL)
    return NULL;
  
  /* We'll return NULL if kCFLocaleLanguageCode doesn't exist.  This is the
     only key that is absolutely necessary.
  */
  if (CFDictionaryGetValueIfPresent(dictionary, kCFLocaleLanguageCode,
      (const void **)&value))
    CFStringGetCString (value, lang, ULOC_LANG_CAPACITY, CFStringGetSystemEncoding());
  else
    return NULL;
  
  hasCountry =
    CFDictionaryGetValueIfPresent(dictionary, kCFLocaleCountryCode,
    (const void **)&value);
  if (hasCountry)
    {
      CFStringGetCString (value, country, ULOC_COUNTRY_CAPACITY,
        CFStringGetSystemEncoding());
    }
  hasScript =
    CFDictionaryGetValueIfPresent(dictionary, kCFLocaleScriptCode,
    (const void **)&value);
  if (hasScript)
    {
      CFStringGetCString (value, script, ULOC_SCRIPT_CAPACITY,
        CFStringGetSystemEncoding());
    }
  hasVariant =
    CFDictionaryGetValueIfPresent(dictionary, kCFLocaleVariantCode,
    (const void **)&value);
  if (hasVariant)
    {
      CFStringGetCString (value, variant, ULOC_KEYWORDS_CAPACITY,
        CFStringGetSystemEncoding());
    }
  
#define TEST_CODE(x, y) (x ? "_" : ""), (x ? y : "")
  snprintf (locale, ULOC_FULLNAME_CAPACITY, "%s%s%s%s%s%s%s",
    lang, TEST_CODE(hasScript, script), TEST_CODE(hasCountry, country),
    TEST_CODE(hasVariant, variant));
#undef TEST_CODE
  // Use uloc_setKeywordValue() here since libicu is a required library.
  if (CFDictionaryGetValueIfPresent(dictionary, kCFLocaleCalendarIdentifier,
      (const void **)&value))
    {
      CFStringGetCString (value, keyword, ULOC_KEYWORDS_CAPACITY,
        CFStringGetSystemEncoding());
      uloc_setKeywordValue ("calendar", keyword, locale,
        ULOC_FULLNAME_CAPACITY, &err);
    }
  if (CFDictionaryGetValueIfPresent(dictionary, kCFLocaleCollationIdentifier,
      (const void **)&value))
    {
      CFStringGetCString (value, keyword, ULOC_KEYWORDS_CAPACITY,
        CFStringGetSystemEncoding());
      uloc_setKeywordValue ("collation", keyword, locale,
        ULOC_FULLNAME_CAPACITY, &err);
    }
  if (CFDictionaryGetValueIfPresent(dictionary, kCFLocaleCurrencyCode,
      (const void **)&value))
    {
      CFStringGetCString (value, keyword, ULOC_KEYWORDS_CAPACITY,
        CFStringGetSystemEncoding());
      uloc_setKeywordValue ("currency", keyword, locale,
        ULOC_FULLNAME_CAPACITY, &err);
    }
  
  return
    CFStringCreateWithCString (allocator, locale, CFStringGetSystemEncoding());
}

CFTypeID
CFLocaleGetTypeID (void)
{
  return _kCFLocaleTypeID;
}

CFStringRef
CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode (CFAllocatorRef allocator,
                                                     uint32_t lcid)
{
  CFStringRef result = NULL;
  char buffer[BUFFER_SIZE];
  UErrorCode err = U_ZERO_ERROR;
  
  uloc_getLocaleForLCID (lcid, buffer, BUFFER_SIZE-1, &err);
  if (U_FAILURE(err) && err != U_BUFFER_OVERFLOW_ERROR)
    return NULL;
  
  result =
    CFStringCreateWithCString (allocator, buffer, CFStringGetSystemEncoding());
  
  return result;
}

CFLocaleLanguageDirection
CFLocaleGetLanguageCharacterDirection (CFStringRef isoLangCode)
{
  char buffer[BUFFER_SIZE];
  ULayoutType result;
  UErrorCode err = U_ZERO_ERROR;
  
  if (!CFStringGetCString (isoLangCode, buffer, BUFFER_SIZE - 1,
      CFStringGetSystemEncoding()))
    return kCFLocaleLanguageDirectionUnknown;
  
  result = uloc_getCharacterOrientation (buffer, &err);
  if (U_FAILURE(err))
    return kCFLocaleLanguageDirectionUnknown;
  
  return ICUToCFLocaleOrientation (result);
}

CFLocaleLanguageDirection
CFLocaleGetLanguageLineDirection (CFStringRef isoLangCode)
{
  char buffer[BUFFER_SIZE];
  ULayoutType result;
  UErrorCode err = U_ZERO_ERROR;
  
  if (!CFStringGetCString (isoLangCode, buffer, BUFFER_SIZE - 1,
      CFStringGetSystemEncoding()))
    return kCFLocaleLanguageDirectionUnknown;
  
  result = uloc_getLineOrientation (buffer, &err);
  if (U_FAILURE(err))
    return kCFLocaleLanguageDirectionUnknown;
  
  return ICUToCFLocaleOrientation (result);
}

uint32_t
CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier (CFStringRef localeIdent)
{
  char buffer[BUFFER_SIZE];
  if (CFStringGetCString (localeIdent, buffer, BUFFER_SIZE - 1,
      CFStringGetSystemEncoding()))
    return uloc_getLCID (buffer);
  return 0;
}