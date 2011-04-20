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
@synthesize webView;

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

- (void)loadLocationDB
{
  NSString* backupPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MobileSync/Backup/"];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray* backupContents = [[NSFileManager defaultManager] directoryContentsAtPath:backupPath];

  NSMutableArray* fileInfoList = [NSMutableArray array];
  for (NSString *childName in backupContents) {
    NSString* childPath = [backupPath stringByAppendingPathComponent:childName];

    NSString *plistFile = [childPath   stringByAppendingPathComponent:@"Info.plist"];
      
    NSError* error;
    NSDictionary *childInfo = [fm attributesOfItemAtPath:childPath error:&error];

    NSDate* modificationDate = [childInfo objectForKey:@"NSFileModificationDate"];    

    NSDictionary* fileInfo = [NSDictionary dictionaryWithObjectsAndKeys: 
      childPath, @"fileName", 
      modificationDate, @"modificationDate", 
      plistFile, @"plistFile", 
      nil];
    [fileInfoList addObject: fileInfo];

  }
  
  NSSortDescriptor* sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"modificationDate" ascending:NO] autorelease];
  [fileInfoList sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];

  BOOL loadWorked = NO;
  for (NSDictionary* fileInfo in fileInfoList) {
    @try {
      NSString* newestFolder = [fileInfo objectForKey:@"fileName"];
      NSString* plistFile = [fileInfo objectForKey:@"plistFile"];
      
      NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistFile];
      if (plist==nil) {
        NSLog(@"No plist file found at '%@'", plistFile);
        continue;
      }
      NSString* deviceName = [plist objectForKey:@"Device Name"];
      NSLog(@"file = %@, device = %@", plistFile, deviceName);  

      NSDictionary* mbdb = [ParseMBDB getFileListForPath: newestFolder];
      if (mbdb==nil) {
        NSLog(@"No MBDB file found at '%@'", newestFolder);
        continue;
      }

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
        NSLog(@"No consolidated.db file found in '%@'", newestFolder);
        continue;
      }

      NSString* dbFilePath = [newestFolder stringByAppendingPathComponent:dbFileName];

      loadWorked = [self tryToLoadLocationDB: dbFilePath forDevice:deviceName];
      if (loadWorked) {
        break;
      }
    }
    @catch (NSException *exception) {
      NSLog(@"Exception: %@", [exception reason]);
    }
  }

  if (!loadWorked) {
    [self displayErrorAndQuit: [NSString stringWithFormat: @"Couldn't load consolidated.db file from '%@'", backupPath]];  
  }
}

- (BOOL)tryToLoadLocationDB:(NSString*) locationDBPath forDevice:(NSString*) deviceName
{
  [scriptObject setValue:self forKey:@"cocoaApp"];
    
  FMDatabase* database = [FMDatabase databaseWithPath: locationDBPath];
  [database setLogsErrors: YES];
  BOOL openWorked = [database open];
  if (!openWorked) {
    return NO;
  }

  const float precision = 100;
  NSMutableDictionary* buckets = [NSMutableDictionary dictionary];

  NSString* queries[] = {@"SELECT * FROM CellLocation;", @"SELECT * FROM WifiLocation;"};
  
  // Temporarily disabled WiFi location pulling, since it's so dodgy. Change to 
  for (int pass=0; pass<1; /*pass<2;*/ pass+=1) {
  
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

  if ([csvArray count]<10) {
    return NO;
  }
  
  NSString* csvText = [csvArray componentsJoinedByString:@"\n"];
  
  [self createKMLOutputWithCSVText:csvText deviceName:deviceName];
    
  id scriptResult = [scriptObject callWebScriptMethod: @"storeLocationData" withArguments:[NSArray arrayWithObjects:csvText,deviceName,nil]];
	if(![scriptResult isMemberOfClass:[WebUndefined class]]) {
		NSLog(@"scriptResult='%@'", scriptResult);
  }

  return YES;
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

- (void)createKMLOutputWithCSVText:(NSString *)csvText deviceName:(NSString *)deviceName
{
    NSMutableString *placemarks = [NSMutableString string];
    
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[csvText componentsSeparatedByString:@"\n"]];
    
    [lines removeObjectAtIndex:0];
    
    for (NSString *line in lines)
    {
        if ([line length])
        {
            NSArray *parts = [line componentsSeparatedByString:@","];
            
            if ([parts count])
            {
                [placemarks appendString:@"<Placemark>\n"];
                [placemarks appendString:[NSString stringWithFormat:@"<name>%@</name>\n", [parts objectAtIndex:3]]];
                [placemarks appendString:[NSString stringWithFormat:@"<description>%@, %@</description>\n", [parts objectAtIndex:1], [parts objectAtIndex:0]]];
                [placemarks appendString:@"<Point>\n"];
                [placemarks appendString:[NSString stringWithFormat:@"<coordinates>%@,%@,0</coordinates>\n", [parts objectAtIndex:1], [parts objectAtIndex:0]]];
                [placemarks appendString:@"</Point>\n"];
                [placemarks appendString:@"</Placemark>\n"];
            }
        }
    }
        
    NSString *template = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"template" ofType:@"kml"] 
                                                   encoding:NSUTF8StringEncoding 
                                                      error:NULL];
    
    template = [template stringByReplacingOccurrencesOfString:@"##NAME##"       withString:deviceName];
    template = [template stringByReplacingOccurrencesOfString:@"##PLACEMARKS##" withString:placemarks];
    
    NSString *fileURL = [NSString stringWithFormat:@"%@/Desktop/%@.kml", NSHomeDirectory(), deviceName];
    
    [template writeToFile:fileURL
               atomically:NO
                 encoding:NSUTF8StringEncoding
                    error:NULL];
    
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:[NSArray arrayWithObject:[NSURL URLWithString:fileURL]]];
}

- (IBAction)openAboutPanel:(id)sender {
    
    NSImage *img = [NSImage imageNamed: @"Icon"];
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
               @"1.0", @"Version",
               @"iPhone Tracking", @"ApplicationName",
               img, @"ApplicationIcon",
               @"Copyright 2011, Pete Warden and Alasdair Allan", @"Copyright",
               @"iPhone Tracking v1.0", @"ApplicationVersion",
               nil];
    
    [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:options];
    
}
@end
