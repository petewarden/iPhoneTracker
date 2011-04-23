//
//  iPhoneTrackingAppDelegate.h
//  iPhoneTracking
//
//  Created by Pete Warden on 4/15/11.
//

/***********************************************************************************
*
* All code (C) Pete Warden, 2011
*
*    This program is free software: you can redistribute it and/or modify
*    it under the terms of the GNU General Public License as published by
*    the Free Software Foundation, either version 3 of the License, or
*    (at your option) any later version.
*
*    This program is distributed in the hope that it will be useful,
*    but WITHOUT ANY WARRANTY; without even the implied warranty of
*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*
*    GNU General Public License for more details.
*
*    You should have received a copy of the GNU General Public License
*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
************************************************************************************/


#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// See http://stackoverflow.com/questions/1496788/building-for-10-5-in-xcode-3-2-on-snow-leopard-error
#if (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_5)
@interface iPhoneTrackingAppDelegate : NSObject
#else
@interface iPhoneTrackingAppDelegate : NSObject <NSApplicationDelegate>
#endif
{
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
