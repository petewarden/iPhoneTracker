//
//  iPhoneTrackingAppDelegate.h
//  iPhoneTracking
//
//  Created by Pete Warden on 4/15/11.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#if (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_5)
@interface iPhoneTrackingAppDelegate : NSObject {
#else
@interface iPhoneTrackingAppDelegate : NSObject <NSApplicationDelegate> {
#endif
  NSWindow *window;
  WebView *webView;
  WebScriptObject* scriptObject;
}

- (void)loadLocationDB;
- (BOOL)tryToLoadLocationDB:(NSString*) locationDBPath forDevice:(NSString*) deviceName;
- (void) incrementBuckets:(NSMutableDictionary*)buckets forKey:(NSString*)key;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet WebView *webView;
- (IBAction)openAboutPanel:(id)sender;

@end
