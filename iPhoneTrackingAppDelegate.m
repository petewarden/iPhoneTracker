//
//  iPhoneTrackingAppDelegate.m
//  iPhoneTracking
//
//  Created by Pete Warden on 4/15/11.
//

#import "iPhoneTrackingAppDelegate.h"
#import "fmdb/FMDatabase.h"
#import "parsembdb.h"

@implementation iPhoneTrackingAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
}

- displayErrorAndQuit:(NSString *)error
{
    [[NSAlert alertWithMessageText: @"Error"
      defaultButton:@"OK" alternateButton:nil otherButton:nil
      informativeTextWithFormat: error] runModal];
    exit(1);
}

- (void)awakeFromNib
{
  NSString* htmlString = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]
      encoding:NSUTF8StringEncoding error:NULL];

 	[[webView mainFrame] loadHTMLString:htmlString baseURL:NULL];
  [webView setUIDelegate:self];
  [webView setFrameLoadDelegate:self]; 
  [webView setResourceLoadDelegate:self]; 
}

- (void)debugLog:(NSString *) message
{
  NSLog(@"%@", message);
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector { return NO; }

- (void)webView:(WebView *)sender windowScriptObjectAvailable: (WebScriptObject *)windowScriptObject
{
  scriptObject = windowScriptObject;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
  [self loadLocationDB];
}

- (NSString*)getLocationDBPath
{
  NSString* backupPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MobileSync/Backup/"];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray* backupContents = [[NSFileManager defaultManager] directoryContentsAtPath:backupPath];
  NSString* newestFolder = nil;
  NSDate* newestDate = nil;

  for (NSString *childName in backupContents) {
    NSString* childPath = [backupPath stringByAppendingPathComponent:childName];

    NSError* error;
    NSDictionary *childInfo = [fm attributesOfItemAtPath:childPath error:&error];

    NSDate* modificationDate = [childInfo objectForKey:@"NSFileModificationDate"];    

    if ((newestDate==nil)||([newestDate compare:modificationDate]==NSOrderedAscending)) {
      newestDate = modificationDate;
      newestFolder = childPath;
    }

  }

  if (newestFolder==nil) {
    [self displayErrorAndQuit:[NSString stringWithFormat: @"Couldn't find backup files at '%@'", backupPath]];  
  }

  NSDictionary* mbdb = [ParseMBDB getFileListForPath: newestFolder];

  NSString* wantedFileName = @"Library/Caches/locationd/consolidated.db";
  NSString* dbFileName = nil;
  for (NSNumber* offset in mbdb) {
    NSDictionary* fileInfo = [mbdb objectForKey:offset];
    NSString* fileName = [fileInfo objectForKey:@"filename"];
    if ([wantedFileName compare:fileName]==NSOrderedSame) {
      dbFileName = [fileInfo objectForKey:@"fileID"];
    }
  }

  if (dbFileName==nil) {
    [self displayErrorAndQuit: [NSString stringWithFormat: @"No consolidated.db file found in '%@'", newestFolder]];
  }

  NSString* dbFilePath = [newestFolder stringByAppendingPathComponent:dbFileName];

  return dbFilePath;
}

- (void)loadLocationDB
{
  [scriptObject setValue:self forKey:@"cocoaApp"];
    
  NSString* locationDBPath = [self getLocationDBPath];
  
  FMDatabase* database = [FMDatabase databaseWithPath: locationDBPath];
  [database setLogsErrors: YES];
  BOOL openWorked = [database open];
  if (!openWorked) {
    [self displayErrorAndQuit:[NSString stringWithFormat: @"Couldn't open location database file '%@'", locationDBPath]];
  }
  
  FMResultSet* results = [database executeQuery:@"SELECT * FROM CellLocation;"];

  const float precision = 100;
  NSMutableDictionary* buckets = [NSMutableDictionary dictionary];

  while ([results next]) {
    NSDictionary* row = [results resultDict];

    NSNumber* latitude_number = [row objectForKey:@"latitude"];
    NSNumber* longitude_number = [row objectForKey:@"longitude"];
    NSNumber* timestamp_number = [row objectForKey:@"timestamp"];

    const float latitude = [latitude_number floatValue];
    const float longitude = [longitude_number floatValue];
    const float timestamp = [timestamp_number floatValue];

    const float latitude_index = (floor(latitude*precision)/precision);  
    const float longitude_index = (floor(longitude*precision)/precision);
    NSString* key = [NSString stringWithFormat:@"%f,%f", latitude_index, longitude_index];

    NSNumber* existingValue = [buckets objectForKey:key];
    if (existingValue==nil) {
      existingValue = [NSNumber numberWithInteger:0];
    }
    NSNumber* newValue = [NSNumber numberWithInteger:([existingValue integerValue]+1)];

    [buckets setObject: newValue forKey: key];
  }
  
  NSMutableArray* csvArray = [[[NSMutableArray alloc] init] autorelease];
  
  [csvArray addObject: @"lat,lon,value\n"];

  for (NSString* key in buckets) {
    NSNumber* count = [buckets objectForKey:key];

    NSArray* parts = [key componentsSeparatedByString:@","];
    NSString* latitude_string = [parts objectAtIndex:0];
    NSString* longitude_string = [parts objectAtIndex:1];

    NSString* rowString = [NSString stringWithFormat:@"%@,%@,%@\n", latitude_string, longitude_string, count];
    [csvArray addObject: rowString];
  }
  
  NSString* csvText = [csvArray componentsJoinedByString:@"\n"];
  
  id scriptResult = [scriptObject callWebScriptMethod: @"storeLocationData" withArguments:[NSArray arrayWithObject:csvText]];
	if(![scriptResult isMemberOfClass:[WebUndefined class]]) {
		NSLog(@"scriptResult='%@'", scriptResult);
  }

}

@end
