#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
static int failures;
static void check_result(const char *label, BOOL ok) { printf("%s %s\n",ok?"PASS":"FAIL",label); failures+=!ok; }
int main(void) { @autoreleasepool {
 char temp[]="/tmp/darling-url-metadata-XXXXXX";char *root=mkdtemp(temp);if(!root)return 2;
 NSString *base=[NSString stringWithUTF8String:root];
 NSString *file=[base stringByAppendingPathComponent:@"file"], *dir=[base stringByAppendingPathComponent:@"dir"];
 int fd=open([file fileSystemRepresentation],O_CREAT|O_EXCL|O_WRONLY,0600);if(fd<0)return 2;write(fd,"test",4);close(fd);
 mkdir([dir fileSystemRepresentation],0700);
 NSArray *names=@[@"file",@"dir",@"file-link",@"dir-link",@"broken-link"];
 symlink("file",[[base stringByAppendingPathComponent:@"file-link"] fileSystemRepresentation]);
 symlink("dir",[[base stringByAppendingPathComponent:@"dir-link"] fileSystemRepresentation]);
 symlink("missing",[[base stringByAppendingPathComponent:@"broken-link"] fileSystemRepresentation]);
 NSArray *keys=@[NSURLIsSymbolicLinkKey,NSURLIsRegularFileKey,NSURLIsDirectoryKey];
 for(NSUInteger i=0;i<[names count];i++) {
  NSString *path=[base stringByAppendingPathComponent:names[i]];
  NSError *error=nil;
  NSDictionary *values=[[NSURL fileURLWithPath:path] resourceValuesForKeys:keys error:&error];
  check_result([[names[i] stringByAppendingString:@" metadata"] UTF8String],values!=nil&&error==nil);
  check_result([[names[i] stringByAppendingString:@" type"] UTF8String],
   [[values objectForKey:NSURLIsSymbolicLinkKey] boolValue]==(i>=2)&&
   [[values objectForKey:NSURLIsRegularFileKey] boolValue]==(i==0)&&
   [[values objectForKey:NSURLIsDirectoryKey] boolValue]==(i==1));
 }
 NSURL *missing=[NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"missing"]];
 NSError *error=nil;
 NSDictionary *values=[missing resourceValuesForKeys:@[NSURLNameKey,NSURLContentModificationDateKey] error:&error];
 check_result("missing request returns nil after a successful lexical property",values==nil&&error!=nil);
 check_result("missing request without error output returns nil",[missing resourceValuesForKeys:@[NSURLContentModificationDateKey] error:NULL]==nil);
 for(NSString *name in names) { NSString *p=[base stringByAppendingPathComponent:name]; if([name isEqual:@"dir"])rmdir([p fileSystemRepresentation]);else unlink([p fileSystemRepresentation]); }
 rmdir(root);
 } printf("failures=%d\n",failures);return failures?1:0; }
