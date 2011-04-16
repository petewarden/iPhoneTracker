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

  const float precision = 100;
  NSMutableDictionary* buckets = [NSMutableDictionary dictionary];

  NSString* queries[] = {@"SELECT * FROM CellLocation;", @"SELECT * FROM WifiLocation;"};
  
  for (int pass=0; pass<2; pass+=1) {
  
    FMResultSet* results = [database executeQuery:queries[pass]];

    while ([results next]) {
      NSDictionary* row = [results resultDict];

      NSNumber* latitude_number = [row objectForKey:@"latitude"];
      NSNumber* longitude_number = [row objectForKey:@"longitude"];
      NSNumber* timestamp_number = [row objectForKey:@"timestamp"];

      const float latitude = [latitude_number floatValue];
      const float longitude = [longitude_number floatValue];
      const float timestamp = [timestamp_number floatValue];
      
      // The timestamps seem to be based off 2001-01-01 strangely, so convert to the 
      // standard Unix form using this offset
      const float iOSToUnixOffset = (31*365.25*24*60*60);
      const float unixTimestamp = (timestamp+iOSToUnixOffset);
      
      if ((latitude==0.0)&&(longitude==0.0)) {
        continue;
      }
      
      const float weekInSeconds = (7*24*60*60);
      const float timeBucket = (floor(unixTimestamp/weekInSeconds)*weekInSeconds);
      
      NSDate* timeBucketDate = [NSDate dateWithTimeIntervalSince1970:timeBucket];

      NSString* timeBucketString = [timeBucketDate descriptionWithCalendarFormat:@"%Y-%m-%d" timeZone:nil locale:nil];

      const float latitude_index = (floor(latitude*precision)/precision);  
      const float longitude_index = (floor(longitude*precision)/precision);
      NSString* allKey = [NSString stringWithFormat:@"%f,%f,All Time", latitude_index, longitude_index];
      NSString* timeKey = [NSString stringWithFormat:@"%f,%f,%@", latitude_index, longitude_index, timeBucketString];

      [self incrementBuckets: buckets forKey: allKey];
      [self incrementBuckets: buckets forKey: timeKey];
    }
  }
  
  NSMutableArray* csvArray = [[[NSMutableArray alloc] init] autorelease];
  
  [csvArray addObject: @"lat,lon,value,time\n"];

  for (NSString* key in buckets) {
    NSNumber* count = [buckets objectForKey:key];

    NSArray* parts = [key componentsSeparatedByString:@","];
    NSString* latitude_string = [parts objectAtIndex:0];
    NSString* longitude_string = [parts objectAtIndex:1];
    NSString* time_string = [parts objectAtIndex:2];

    NSString* rowString = [NSString stringWithFormat:@"%@,%@,%@,%@\n", latitude_string, longitude_string, count, time_string];
    [csvArray addObject: rowString];
  }
  
  NSString* csvText = [csvArray componentsJoinedByString:@"\n"];
  
  id scriptResult = [scriptObject callWebScriptMethod: @"storeLocationData" withArguments:[NSArray arrayWithObject:csvText]];
	if(![scriptResult isMemberOfClass:[WebUndefined class]]) {
		NSLog(@"scriptResult='%@'", scriptResult);
  }

}

- (void) incrementBuckets:(NSMutableDictionary*)buckets forKey:(NSString*)key
{
    NSNumber* existingValue = [buckets objectForKey:key];
    if (existingValue==nil) {
      existingValue = [NSNumber numberWithInteger:0];
    }
    NSNumber* newValue = [NSNumber numberWithInteger:([existingValue integerValue]+1)];

    [buckets setObject: newValue forKey: key];
}

@end
