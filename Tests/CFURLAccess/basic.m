#include "CoreFoundation/CFURLAccess.h"
#include "CoreFoundation/CFNumber.h"
#include "../CFTesting.h"
#include <string.h>

const char *test = "test data!\n";

int main (void)
{
  const char *bytes;
  CFURLRef dir;
  CFURLRef file1;
  CFURLRef file2;
  CFDataRef data;
  CFDictionaryRef dict;
  CFArrayRef contents;
  CFNumberRef num;
  CFIndex fileLength;
  CFIndex count;
  
  dir = CFURLCreateWithFileSystemPath (NULL, CFSTR("TestDir"),
    kCFURLPOSIXPathStyle, true);
  PASS (CFURLWriteDataAndPropertiesToResource (dir, NULL, NULL, NULL),
    "Directory was successfully created.");
  CFURLRef tmp = CFURLCopyAbsoluteURL (dir);
  PASS_CFEQ (CFURLGetString(tmp), CFSTR(""), "Absolute path to TestDir/.");
  CFRelease (tmp);
  
  file1 = CFURLCreateWithFileSystemPath (NULL, CFSTR("TestDir/file1.txt"),
    kCFURLPOSIXPathStyle, false);
  data = CFDataCreate (NULL, (const UInt8*)test, strlen(test));
  
  PASS (CFURLWriteDataAndPropertiesToResource (file1, data, NULL, NULL),
    "Data was successfully written to test file.");
  
  CFRelease (data);
  
  file2 = CFURLCreateWithFileSystemPath (NULL, CFSTR("TestDir/file2.txt"),
    kCFURLPOSIXPathStyle, false);
  data = CFDataCreate (NULL, NULL, 0);
  
  PASS (CFURLWriteDataAndPropertiesToResource (file2, data, NULL, NULL),
    "Empty file was successfully created.");
  
  CFRelease (data);
  
  /* Lets try to delete the directory with files inside, this should fail. */
  PASS (!CFURLDestroyResource(dir, NULL), "Could not delete directory.");
  
  PASS (CFURLCreateDataAndPropertiesFromResource (NULL, file1, &data, &dict,
    NULL, NULL), "File was successfully read.");
  num = CFDictionaryGetValue (dict, kCFURLFileLength);
  CFNumberGetValue (num, kCFNumberCFIndexType, &fileLength);
  PASS (fileLength == 11, "Properties correctly read.");
  
  CFRelease (dict);
  
  PASS (CFURLCreateDataAndPropertiesFromResource (NULL, dir, NULL, &dict,
    NULL, NULL), "Directory was successfully read.");
  contents = CFDictionaryGetValue (dict, kCFURLFileDirectoryContents);
  count = CFArrayGetCount (contents);
  PASS (count == 2, "There are %d items in the directory.", (int)count);
  PASS (CFArrayContainsValue (contents, CFRangeMake (0, count), CFSTR("file1.txt")),
    "Directory has file1.txt");
  PASS (CFArrayContainsValue (contents, CFRangeMake (0, count), CFSTR("file2.txt")),
    "Directory has file2.txt");
  
  CFRelease (dict);
  
  bytes = (const char*)CFDataGetBytePtr (data);
  PASS (strncmp (bytes, test, strlen(test)) == 0,
    "Content read is the same the content that was written.");
  
  CFRelease (data);
  
  PASS (CFURLDestroyResource(file1, NULL), "File1 was successfully deleted.");
  PASS (CFURLDestroyResource(file2, NULL), "File2 was successfully deleted.");
  PASS (CFURLDestroyResource(dir, NULL), "Directory was successfully deleted.");
  
  CFRelease (file1);
  CFRelease (file2);
  CFRelease (dir);
  
  return 0;
}