#include "config.h"

#if __FLTK_IPHONEOS__

#include "Fl.H"
#include "x.H"
#include "Fl_Window.H"
#include "Fl_Tooltip.H"
#include "Fl_Printer.H"
#include "Fl_Input_.H"
#include "Fl_Text_Display.H"
#include <stdio.h>
#include <stdlib.h>
#include "flstring.h"
#include <unistd.h>
#include <stdarg.h>
#include <math.h>
#include <limits.h>

//#include <sys/time.h>

#include "Fl_Device.H"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ======================================================
/*
 *  System Versioning Preprocessor Macros
 */

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

/*
//  Usage
if (SYSTEM_VERSION_LESS_THAN(@"4.0")) {
    ...
}
if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"3.1.1")) {
    ...
}
*/
// ======================================================

static unsigned make_current_counts = 0; // if > 0, then Fl_Window::make_current() can be called only once
static Fl_X *fl_x_to_redraw = NULL;
static BOOL through_drawRect = NO;

static Fl_Quartz_Graphics_Driver fl_quartz_driver;
static Fl_Display_Device fl_quartz_display(&fl_quartz_driver);
Fl_Display_Device *Fl_Display_Device::_display = &fl_quartz_display; // the platform display

// these pointers are set by the Fl::lock() function:
static void nothing() { }
void (*fl_lock_function)() = nothing;
void (*fl_unlock_function)() = nothing;

static int device_w, device_h, work_y=0;

static void handleUpdateEvent(Fl_Window *window);

static NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:-0.001];

// ************************* main begin ****************************************
static int forward_argc;
static char **forward_argv;
static int exit_status;

static unsigned char EventPumpEnabled_ = 0;
static void SetEventPump(unsigned char enabled)
{
	EventPumpEnabled_ = enabled;
}

#define FLTK_min(x, y) (((x) < (y)) ? (x) : (y))
#define FLTK_max(x, y) (((x) > (y)) ? (x) : (y))
@interface FLTK_splashviewcontroller : UIViewController {
    UIImageView *splash;
    UIImage *splashPortrait;
    UIImage *splashLandscape;
}

- (void)updateSplashImage:(UIInterfaceOrientation)interfaceOrientation;
@end

@implementation FLTK_splashviewcontroller

- (id)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    [self setWantsFullScreenLayout:YES];

    self->splash = [[UIImageView alloc] init];
    [self setView:self->splash];

    CGSize size = [UIScreen mainScreen].bounds.size;
    float height = FLTK_max(size.width, size.height);
    self->splashPortrait = [UIImage imageNamed:[NSString stringWithFormat:@"Default-%dh.png", (int)height]];
    if (!self->splashPortrait) {
        self->splashPortrait = [UIImage imageNamed:@"Default.png"];
    }
    self->splashLandscape = [UIImage imageNamed:@"Default-Landscape.png"];
    if (!self->splashLandscape && self->splashPortrait) {
        self->splashLandscape = [[UIImage alloc] initWithCGImage: self->splashPortrait.CGImage
                                                           scale: 1.0
                                                     orientation: UIImageOrientationRight];
    }
    if (self->splashPortrait) {
        [self->splashPortrait retain];
    }
    if (self->splashLandscape) {
        [self->splashLandscape retain];
    }

    [self updateSplashImage:[[UIApplication sharedApplication] statusBarOrientation]];

    return self;
}

- (NSUInteger)supportedInterfaceOrientations
{
    NSUInteger orientationMask = UIInterfaceOrientationMaskAll;

    /* Don't allow upside-down orientation on the phone, so answering calls is in the natural orientation */
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        orientationMask &= ~UIInterfaceOrientationMaskPortraitUpsideDown;
    }
    return orientationMask;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orient
{
    NSUInteger orientationMask = [self supportedInterfaceOrientations];
    return (orientationMask & (1 << orient));
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    [self updateSplashImage:interfaceOrientation];
    printf("will rotation\n");
}

- (void)updateSplashImage:(UIInterfaceOrientation)interfaceOrientation
{
    UIImage *image;

    if (UIInterfaceOrientationIsLandscape(interfaceOrientation)) {
        image = self->splashLandscape;
    } else {
        image = self->splashPortrait;
    }
    if (image)
    {
        splash.image = image;
    }
}

@end

static UIWindow *launch_window=nil;
@interface FLTKUIKitDelegate : NSObject<UIApplicationDelegate> {	
}
+ (NSString *)getAppDelegateClassName;
@end

@implementation FLTKUIKitDelegate

+ (NSString *)getAppDelegateClassName
{
    return @"FLTKUIKitDelegate";
}

- (id)init
{
    self = [super init];
    return self;
}

- (void)postFinishLaunch
{
	CGSize size = [UIScreen mainScreen].bounds.size;
    Fl_Window::DisplayOrientation ori = Fl_Window::getCurrentOrientation();
    if ( ori == Fl_Window::upright || ori == Fl_Window::upsideDown )
    device_w = (int)size.width; device_h = (int)size.height;
    //printf("decive_h=%d\n", device_h);
    
    [[UIApplication sharedApplication] setStatusBarHidden:NO];
    //[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:NO];
    
    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
	work_y = bounds.origin.y;
	
    /* run the user's application, passing argc and argv */
    SetEventPump(1);
    exit_status = IOS_main(forward_argc, forward_argv);
    SetEventPump(0);

    /* If we showed a splash image, clean it up */
    if (launch_window) {
        [launch_window release];
        launch_window = NULL;
    }

    /* exit, passing the return status from the user's application */
    /* We don't actually exit to support applications that do setup in
     * their main function and then allow the Cocoa event loop to run.
     */
    /* exit(exit_status); */
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    /* Keep the launch image up until we set a video mode */
    CGRect crect =[[UIScreen mainScreen] bounds];
	launch_window = [[UIWindow alloc] initWithFrame:crect];
    FLTK_splashviewcontroller *splashViewController = [[FLTK_splashviewcontroller alloc] init];
    launch_window.rootViewController = splashViewController;
    [launch_window addSubview:splashViewController.view];
    [launch_window makeKeyAndVisible];

    /* Set working directory to resource path */
    [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] resourcePath]];

    [self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0];

    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	fl_lock_function();
	while (Fl_X::first) {
		Fl_X *x = Fl_X::first;
		Fl::handle(FL_CLOSE, x->w);
		Fl::do_widget_deletion();
		if (Fl_X::first == x) {
			// FLTK has not closed all windows, so we return to the main program now
			break;
		}
	}
	fl_unlock_function();
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    //SDL_SendAppEvent(SDL_APP_LOWMEMORY);
	// Do something
}

// http://justcoding.iteye.com/blog/1473350
/*
首次运行：
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
- (void)applicationDidBecomeActive:(UIApplication *)application

首次关闭（home）：
- (void)applicationWillResignActive:(UIApplication *)application
- (void)applicationDidEnterBackground:(UIApplication *)application

再次运行：
- (void)applicationWillEnterForeground:(UIApplication *)application
- (void)applicationDidBecomeActive:(UIApplication *)application

再次关闭：
- (void)applicationWillResignActive:(UIApplication *)application
- (void)applicationDidEnterBackground:(UIApplication *)application
*/
- (void) applicationWillResignActive:(UIApplication*)application
{
	// FIXIT: send event
}

- (void) applicationDidEnterBackground:(UIApplication*)application
{
	// FIXIT: send event
}

- (void) applicationWillEnterForeground:(UIApplication*)application
{
	// FIXIT: send event
}

- (void) applicationDidBecomeActive:(UIApplication*)application
{
	// FIXIT: send event
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
/*
    NSURL *fileURL = [url filePathURL];
    if (fileURL != nil) {
        SDL_SendDropFile([[fileURL path] UTF8String]);
    } else {
        SDL_SendDropFile([[url absoluteString] UTF8String]);
    }
*/	
	// FIXIT:
	
    return YES;
}

@end

#ifdef main
#undef main
#endif
int main(int argc, char **argv)
{
    int i;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* store arguments */
    forward_argc = argc;
    forward_argv = (char **)malloc((argc+1) * sizeof(char *));
    for (i = 0; i < argc; i++) {
        forward_argv[i] = (char*)malloc( (strlen(argv[i])+1) * sizeof(char));
        strcpy(forward_argv[i], argv[i]);
    }
    forward_argv[i] = NULL;
    
    /* Give over control to run loop, FLTKUIKitDelegate will handle most things from here */
    UIApplicationMain(argc, argv, NULL, [FLTKUIKitDelegate getAppDelegateClassName]);

    /* free the memory we used to hold copies of argc and argv */
    for (i = 0; i < forward_argc; i++) {
        free(forward_argv[i]);
    }
    free(forward_argv);

    [pool release];
    return exit_status;
}
// ************************* main end ****************************************

// type:0-begin,1-move,2-end
static void iosMouseHandler(NSSet *touches, UIEvent *event, UIView *view, int type);

//==============================================================================
@interface FLView : UIView <UITextViewDelegate>
{
	BOOL in_key_event; // YES means keypress is being processed by handleEvent
	BOOL need_handle; // YES means Fl::handle(FL_KEYBOARD,) is needed after handleEvent processing
	NSInteger identifier;
	NSRange selectedRange;
	
@public
    UITextView* hiddenTextView;
	Fl_Window *flwindow;
}
- (FLView*) initWithFlWindow: (Fl_Window*)win contentRect: (CGRect) rect;
- (Fl_Window *)getFl_Window;
- (void) dealloc;

- (void) drawRect: (CGRect) r;

- (void) touchesBegan: (NSSet*) touches withEvent: (UIEvent*) event;
- (void) touchesMoved: (NSSet*) touches withEvent: (UIEvent*) event;
- (void) touchesEnded: (NSSet*) touches withEvent: (UIEvent*) event;
- (void) touchesCancelled: (NSSet*) touches withEvent: (UIEvent*) event;

- (BOOL) becomeFirstResponder;
- (BOOL) resignFirstResponder;
- (BOOL) canBecomeFirstResponder;

- (BOOL) textView: (UITextView*) textView shouldChangeTextInRange: (NSRange) range replacementText: (NSString*) text;
@end

//==============================================================================
@interface FLViewController : UIViewController
{
}
- (NSUInteger) supportedInterfaceOrientations;
- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation;
- (void) willRotateToInterfaceOrientation: (UIInterfaceOrientation) toInterfaceOrientation duration: (NSTimeInterval) duration;
- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation;
- (BOOL)prefersStatusBarHidden;
@end

//==============================================================================
@interface FLWindow : UIWindow {
    Fl_Window *w;
}
- (FLWindow *)initWithFlWindow: (Fl_Window *)flw contentRect: (CGRect)rect;
- (Fl_Window *)getFl_Window;
- (void) becomeKeyWindow;
@end
//==============================================================================
/*
@implementation FLView
- (id)initWithFrame:(CGRect)rect
{
    self = [super initWithFrame : rect];
    
    if (self != nil) {
        //textView = [[UITextView alloc] initWithFrame : rect];
        //textView.text = @"你好Hello world!";
        //[self addSubview : textView];
    }
    
    return self;
}

- (id)init
{
	static NSInteger counter = 0;
	self = [super init];
	if (self) {
		in_key_event = NO;
		identifier = ++counter;
	}
    
    edit = [[UITextField alloc] initWithFrame:CGRectMake(20, 40, 120, 120)];
    [self addSubview:edit];
    
    [edit becomeFirstResponder];
    
	return self;
}

- (void)dealloc
{
    [edit release];
    [super dealloc];
}

- (void)drawRect: (CGRect)rect
{
	fl_lock_function();
	through_drawRect = YES;
	FLWindow *cw = (FLWindow *)[self window];
	Fl_Window *w = [cw getFl_Window];
	if (fl_x_to_redraw) fl_x_to_redraw->flush();
	else handleUpdateEvent(w);
	through_drawRect = NO;
	fl_unlock_function();
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    printf("click\n");
    iosMouseHandler(touches, event, self, 0);
  */  /*
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];
    NSUInteger taps = [touch tapCount];
    
    printf("%s tap at %f %f, tap count: %d\n", (taps==1)?"Single":(taps==2)?"Double":"Triple++", location.x, location.y, taps);
     */
/*}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    iosMouseHandler(touches, event, self, 1);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    iosMouseHandler(touches, event, self, 2);
}
*/
/*
- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (BOOL)performKeyEquivalent: (NSEvent *)theEvent
{
	//NSLog(@"performKeyEquivalent:");
	fl_lock_function();
	cocoaKeyboardHandler(theEvent);
	BOOL handled;
	NSUInteger mods = [theEvent modifierFlags];
	if ((mods & NSControlKeyMask) || (mods & NSCommandKeyMask)) {
		NSString *s = [theEvent characters];
		if ((mods & NSShiftKeyMask) && (mods & NSCommandKeyMask)) {
			s = [s uppercaseString]; // US keyboards return lowercase letter in s if cmd-shift-key is hit
		}
		[FLView prepareEtext: s];
		Fl::compose_state = 0;
		handled = Fl::handle(FL_KEYBOARD, [(FLWindow *)[theEvent window] getFl_Window]);
	} else {
		in_key_event = YES;
		need_handle = NO;
		handled = [[self performSelector: inputContextSEL] handleEvent: theEvent];
		if (need_handle) handled = Fl::handle(FL_KEYBOARD, [(FLWindow *)[theEvent window] getFl_Window]);
		in_key_event = NO;
	}
	fl_unlock_function();
	return handled;
}
- (BOOL)acceptsFirstMouse: (NSEvent *)theEvent
{
	Fl_Window *w = [(FLWindow *)[theEvent window] getFl_Window];
	Fl_Window *first = Fl::first_window();
	return (first == w || !first->modal());
}
- (void)resetCursorRects
{
	Fl_Window *w = [(FLWindow *)[self window] getFl_Window];
	Fl_X *i = Fl_X::i(w);
	if (!i) return;  // fix for STR #3128
	// We have to have at least one cursor rect for invalidateCursorRectsForView
	// to work, hence the "else" clause.
	if (i->cursor) [self addCursorRect: [self visibleRect] cursor: (NSCursor *)i->cursor];
	else [self addCursorRect: [self visibleRect] cursor: [NSCursor arrowCursor]];
}
- (void)mouseUp: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)rightMouseUp: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)otherMouseUp: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)mouseDown: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)rightMouseDown: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)otherMouseDown: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)mouseMoved: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)mouseDragged: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)rightMouseDragged: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)otherMouseDragged: (NSEvent *)theEvent
{
	cocoaMouseHandler(theEvent);
}
- (void)scrollWheel: (NSEvent *)theEvent
{
	cocoaMouseWheelHandler(theEvent);
}
- (void)keyDown: (NSEvent *)theEvent
{
	//NSLog(@"keyDown:%@",[theEvent characters]);
	fl_lock_function();
	Fl_Window *window = [(FLWindow *)[theEvent window] getFl_Window];
	Fl::first_window(window);
	cocoaKeyboardHandler(theEvent);
	in_key_event = YES;
	need_handle = NO;
	[[self performSelector: inputContextSEL] handleEvent: theEvent];
	if (need_handle) Fl::handle(FL_KEYBOARD, window);
	in_key_event = NO;
	fl_unlock_function();
}
- (void)keyUp: (NSEvent *)theEvent
{
	//NSLog(@"keyUp:%@",[theEvent characters]);
	fl_lock_function();
	Fl_Window *window = (Fl_Window *)[(FLWindow *)[theEvent window] getFl_Window];
	Fl::first_window(window);
	cocoaKeyboardHandler(theEvent);
	NSString *s = [theEvent characters];
	if ([s length] >= 1) [FLView prepareEtext: [s substringToIndex: 1]];
	Fl::handle(FL_KEYUP, window);
	fl_unlock_function();
}
- (void)flagsChanged: (NSEvent *)theEvent
{
	//NSLog(@"flagsChanged: ");
	fl_lock_function();
	static UInt32 prevMods = 0;
	NSUInteger mods = [theEvent modifierFlags];
	Fl_Window *window = (Fl_Window *)[(FLWindow *)[theEvent window] getFl_Window];
	UInt32 tMods = prevMods ^ mods;
	int sendEvent = 0;
	if (tMods) {
		unsigned short keycode = [theEvent keyCode];
		Fl::e_keysym = Fl::e_original_keysym = macKeyLookUp[keycode & 0x7f];
		if (Fl::e_keysym) sendEvent = (prevMods < mods) ? FL_KEYBOARD : FL_KEYUP;
		Fl::e_length = 0;
		Fl::e_text = (char *)"";
		prevMods = mods;
	}
	mods_to_e_state(mods);
	while (window->parent()) window = window->window();
	if (sendEvent) Fl::handle(sendEvent, window);
	fl_unlock_function();
}
- (NSDragOperation)draggingEntered: (id<NSDraggingInfo>)sender
{
	fl_lock_function();
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	update_e_xy_and_e_xy_root([self window]);
	fl_dnd_target_window = target;
	int ret = Fl::handle(FL_DND_ENTER, target);
	breakMacEventLoop();
	fl_unlock_function();
	Fl::flush();
	return ret ? NSDragOperationCopy : NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated: (id<NSDraggingInfo>)sender
{
	fl_lock_function();
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	update_e_xy_and_e_xy_root([self window]);
	fl_dnd_target_window = target;
	int ret = Fl::handle(FL_DND_DRAG, target);
	breakMacEventLoop();
	fl_unlock_function();
	// if the DND started in the same application, Fl::dnd() will not return until
	// the the DND operation is finished. The call below causes the drop indicator
	// to be draw correctly (a full event handling would be better...)
	Fl::flush();
	return ret ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation: (id<NSDraggingInfo>)sender
{
	static char *DragData = NULL;
	fl_lock_function();
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	if (!Fl::handle(FL_DND_RELEASE, target)) {
		breakMacEventLoop();
		fl_unlock_function();
		return NO;
	}
	NSPasteboard *pboard;
	// NSDragOperation sourceDragMask;
	// sourceDragMask = [sender draggingSourceOperationMask];
	pboard = [sender draggingPasteboard];
	update_e_xy_and_e_xy_root([self window]);
	if (DragData) {free(DragData); DragData = NULL; }
	if ([[pboard types] containsObject: NSFilenamesPboardType]) {
		CFArrayRef files = (CFArrayRef)[pboard propertyListForType: NSFilenamesPboardType];
		CFStringRef all = CFStringCreateByCombiningStrings(NULL, files, CFSTR("\n"));
		int l = CFStringGetMaximumSizeForEncoding(CFStringGetLength(all), kCFStringEncodingUTF8);
		DragData = (char *)malloc(l + 1);
		CFStringGetCString(all, DragData, l + 1, kCFStringEncodingUTF8);
		CFRelease(all);
	} else if ([[pboard types] containsObject: utf8_format]) {
		NSData *data = [pboard dataForType: utf8_format];
		DragData = (char *)malloc([data length] + 1);
		[data getBytes: DragData];
		DragData[[data length]] = 0;
		convert_crlf(DragData, strlen(DragData));
	} else {
		breakMacEventLoop();
		fl_unlock_function();
		return NO;
	}
	Fl::e_text = DragData;
	Fl::e_length = strlen(DragData);
	int old_event = Fl::e_number;
	Fl::belowmouse()->handle(Fl::e_number = FL_PASTE);
	Fl::e_number = old_event;
	if (DragData) {free(DragData); DragData = NULL; }
	Fl::e_text = NULL;
	Fl::e_length = 0;
	fl_dnd_target_window = NULL;
	breakMacEventLoop();
	fl_unlock_function();
	return YES;
}
- (void)draggingExited: (id<NSDraggingInfo>)sender
{
	fl_lock_function();
	if (fl_dnd_target_window) {
		Fl::handle(FL_DND_LEAVE, fl_dnd_target_window);
		fl_dnd_target_window = 0;
	}
	fl_unlock_function();
}
- (NSDragOperation)draggingSourceOperationMaskForLocal: (BOOL)isLocal
{
	return NSDragOperationGeneric;
}

- (FLTextInputContext *)FLinputContext { // used only if OS < 10.6 to replace [NSView inputContext]
	static FLTextInputContext *context = NULL;
	if (!context) {
		context = [[FLTextInputContext alloc] init];
	}
	context->edit = (FLTextView *)[[self window] fieldEditor: YES forObject: nil];
	return context;
}

+ (void)prepareEtext: (NSString *)aString
{
	// fills Fl::e_text with UTF-8 encoded aString using an adequate memory allocation
	static char *received_utf8 = NULL;
	static int lreceived = 0;
	char *p = (char *)[aString UTF8String];
	int l = strlen(p);
	if (l > 0) {
		if (lreceived == 0) {
			received_utf8 = (char *)malloc(l + 1);
			lreceived = l;
		} else if (l > lreceived) {
			received_utf8 = (char *)realloc(received_utf8, l + 1);
			lreceived = l;
		}
		strcpy(received_utf8, p);
		Fl::e_text = received_utf8;
	}
	Fl::e_length = l;
}

+ (void)concatEtext: (NSString *)aString
{
	// extends Fl::e_text with aString
	NSString *newstring = [[NSString stringWithUTF8String: Fl::e_text] stringByAppendingString: aString];
	[FLView prepareEtext: newstring];
}

- (void)doCommandBySelector: (SEL)aSelector
{
	NSString *s = [[NSApp currentEvent] characters];
	//NSLog(@"doCommandBySelector:%s text='%@'",sel_getName(aSelector), s);
	s = [s substringFromIndex: [s length] - 1];
	[FLView prepareEtext: s]; // use the last character of the event; necessary for deadkey + Tab
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	Fl::handle(FL_KEYBOARD, target);
}

- (void)insertText: (id)aString
{
	[self insertText: aString replacementRange: NSMakeRange(NSNotFound, 0)];
}

- (void)insertText: (id)aString replacementRange: (NSRange)replacementRange
{
	NSString *received;
	if ([aString isKindOfClass: [NSAttributedString class]]) {
		received = [(NSAttributedString *)aString string];
	} else {
		received = (NSString *)aString;
	}
	//NSLog(@"insertText='%@' l=%d Fl::compose_state=%d range=%d,%d", received,strlen([received UTF8String]),Fl::compose_state,replacementRange.location,replacementRange.length);
	fl_lock_function();
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	while (replacementRange.length--) { // delete replacementRange.length characters before insertion point
		int saved_keysym = Fl::e_keysym;
		Fl::e_keysym = FL_BackSpace;
		Fl::handle(FL_KEYBOARD, target);
		Fl::e_keysym = saved_keysym;
	}
	if (in_key_event && Fl_X::next_marked_length && Fl::e_length) {
		// if setMarkedText + insertText is sent during handleEvent, text cannot be concatenated in single FL_KEYBOARD event
		Fl::handle(FL_KEYBOARD, target);
		Fl::e_length = 0;
	}
	if (in_key_event && Fl::e_length) [FLView concatEtext: received];
	else [FLView prepareEtext: received];
	Fl_X::next_marked_length = 0;
	// We can get called outside of key events (e.g., from the character palette, from CJK text input).
	BOOL palette = !(in_key_event || Fl::compose_state);
	if (palette) Fl::e_keysym = 0;
	// YES if key has text attached
	BOOL has_text_key = Fl::e_keysym <= '~' || Fl::e_keysym == FL_Iso_Key ||
		(Fl::e_keysym >= FL_KP && Fl::e_keysym <= FL_KP_Last && Fl::e_keysym != FL_KP_Enter);
	// insertText sent during handleEvent of a key without text cannot be processed in a single FL_KEYBOARD event.
	// Occurs with deadkey followed by non-text key
	if (!in_key_event || !has_text_key) {
		Fl::handle(FL_KEYBOARD, target);
		Fl::e_length = 0;
	} else need_handle = YES;
	selectedRange = NSMakeRange(100, 0); // 100 is an arbitrary value
										 // for some reason, with the palette, the window does not redraw until the next mouse move or button push
										 // sending a 'redraw()' or 'awake()' does not solve the issue!
	if (palette) Fl::flush();
	if (fl_mac_os_version < 100600) [(FLTextView *)[[self window] fieldEditor: YES forObject: nil] setActive: NO];
	fl_unlock_function();
}

- (void)setMarkedText: (id)aString selectedRange: (NSRange)newSelection
{
	[self setMarkedText: aString selectedRange: newSelection replacementRange: NSMakeRange(NSNotFound, 0)];
}

- (void)setMarkedText: (id)aString selectedRange: (NSRange)newSelection replacementRange: (NSRange)replacementRange
{
	NSString *received;
	if ([aString isKindOfClass: [NSAttributedString class]]) {
		received = [(NSAttributedString *)aString string];
	} else {
		received = (NSString *)aString;
	}
	fl_lock_function();
	//NSLog(@"setMarkedText:%@ l=%d newSelection=%d,%d Fl::compose_state=%d replacement=%d,%d", 
	//  received, strlen([received UTF8String]), newSelection.location, newSelection.length, Fl::compose_state,
	//  replacementRange.location, replacementRange.length);
	Fl_Window *target = [(FLWindow *)[self window] getFl_Window];
	while (replacementRange.length--) { // delete replacementRange.length characters before insertion point
		Fl::e_keysym = FL_BackSpace;
		Fl::compose_state = 0;
		Fl_X::next_marked_length = 0;
		Fl::handle(FL_KEYBOARD, target);
		Fl::e_keysym = 'a'; // pretend a letter key was hit
	}
	if (in_key_event && Fl_X::next_marked_length && Fl::e_length) {
		// if setMarkedText + setMarkedText is sent during handleEvent, text cannot be concatenated in single FL_KEYBOARD event
		Fl::handle(FL_KEYBOARD, target);
		Fl::e_length = 0;
	}
	if (in_key_event && Fl::e_length) [FLView concatEtext: received];
	else [FLView prepareEtext: received];
	Fl_X::next_marked_length = strlen([received UTF8String]);
	if (!in_key_event) Fl::handle(FL_KEYBOARD, target);
	else need_handle = YES;
	selectedRange = NSMakeRange(100, newSelection.length);
	fl_unlock_function();
}

- (void)unmarkText
{
	fl_lock_function();
	Fl::reset_marked_text();
	fl_unlock_function();
	//NSLog(@"unmarkText");
}

- (NSRange)selectedRange
{
	Fl_Widget *w = Fl::focus();
	if (w && w->use_accents_menu()) return selectedRange;
	return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange
{
	//NSLog(@"markedRange=%d %d", Fl::compose_state > 0?0:NSNotFound, Fl::compose_state);
	return NSMakeRange(Fl::compose_state > 0 ? 0 : NSNotFound, Fl::compose_state);
}

- (BOOL)hasMarkedText
{
	//NSLog(@"hasMarkedText %s", Fl::compose_state > 0?"YES":"NO");
	return (Fl::compose_state > 0);
}

- (NSAttributedString *)attributedSubstringFromRange: (NSRange)aRange
{
	return [self attributedSubstringForProposedRange: aRange actualRange: NULL];
}
- (NSAttributedString *)attributedSubstringForProposedRange: (NSRange)aRange actualRange: (NSRangePointer)actualRange
{
	//NSLog(@"attributedSubstringFromRange: %d %d",aRange.location,aRange.length);
	return nil;
}

- (NSArray *)validAttributesForMarkedText
{
	return nil;
}

- (NSRect)firstRectForCharacterRange: (NSRange)aRange
{
	return [self firstRectForCharacterRange: aRange actualRange: NULL];
}
- (NSRect)firstRectForCharacterRange: (NSRange)aRange actualRange: (NSRangePointer)actualRange
{
	//NSLog(@"firstRectForCharacterRange %d %d actualRange=%p",aRange.location, aRange.length,actualRange);
	NSRect glyphRect;
	fl_lock_function();
	Fl_Widget *focus = Fl::focus();
	Fl_Window *wfocus = [(FLWindow *)[self window] getFl_Window];
	if (!focus) focus = wfocus;
	glyphRect.size.width = 0;

	int x, y, height;
	if (Fl_X::insertion_point_location(&x, &y, &height)) {
		glyphRect.origin.x = (CGFloat)x;
		glyphRect.origin.y = (CGFloat)y;
	} else {
		if (focus->as_window()) {
			glyphRect.origin.x = 0;
			glyphRect.origin.y = focus->h();
		} else {
			glyphRect.origin.x = focus->x();
			glyphRect.origin.y = focus->y() + focus->h();
		}
		height = 12;
	}
	glyphRect.size.height = height;
	Fl_Window *win = focus->as_window();
	if (!win) win = focus->window();
	while (win != NULL && win != wfocus) {
		glyphRect.origin.x += win->x();
		glyphRect.origin.y += win->y();
		win = win->window();
	}
	// Convert the rect to screen coordinates
	glyphRect.origin.y = wfocus->h() - glyphRect.origin.y;
	glyphRect.origin = [(FLWindow*)[self window] convertBaseToScreen:glyphRect.origin];
	if (actualRange) *actualRange = aRange;
	fl_unlock_function();
	return glyphRect;
}

- (NSUInteger)characterIndexForPoint: (NSPoint)aPoint
{
	return 0;
}

- (NSInteger)windowLevel
{
	return [[self window] level];
}

- (NSInteger)conversationIdentifier
{
	return identifier;
}
*/
//@end

/*
// updates Fl::e_x, Fl::e_y, Fl::e_x_root, and Fl::e_y_root
static void update_e_xy_and_e_xy_root(UIWindow *nsw)
{
    NSPoint pt;
    pt = [nsw mouseLocationOutsideOfEventStream];
    Fl::e_x = int(pt.x);
    Fl::e_y = int([[nsw contentView] frame].size.height - pt.y);
    pt = [NSEvent mouseLocation];
    Fl::e_x_root = int(pt.x);
    Fl::e_y_root = int(main_screen_height - pt.y);
}
*/

static void iosMouseHandler(NSSet *touches, UIEvent *event, UIView *view, int type)
{
    static int keysym[] = { 0, FL_Button + 1, FL_Button + 3, FL_Button + 2 };
    static int px, py;
    static char suppressed = 0;
    
    fl_lock_function();
    
    Fl_Window *window = (Fl_Window *)[(FLWindow *)[view window] getFl_Window];
    if (!window->shown()) {
        fl_unlock_function();
        return;
    }
    
    Fl_Window *first = Fl::first_window();
    if (first != window && !(first->modal() || first->non_modal())) Fl::first_window(window);
    
    UITouch *touch = [touches anyObject];
    CGPoint pos = [touch locationInView:view];
    NSUInteger taps = [touch tapCount];
    //pos.y = window->h() - pos.y;
    NSInteger btn = 1;//[theEvent buttonNumber]  + 1;
    //NSUInteger mods = [theEvent modifierFlags];
    int sendEvent = 0;
    
    /*
     NSEventType etype = [theEvent type];
     if (etype == NSLeftMouseDown || etype == NSRightMouseDown || etype == NSOtherMouseDown) {
     if (btn == 1) Fl::e_state |= FL_BUTTON1;
     else if (btn == 3) Fl::e_state |= FL_BUTTON2;
     else if (btn == 2) Fl::e_state |= FL_BUTTON3;
     } else if (etype == NSLeftMouseUp || etype == NSRightMouseUp || etype == NSOtherMouseUp) {
     if (btn == 1) Fl::e_state &= ~FL_BUTTON1;
     else if (btn == 3) Fl::e_state &= ~FL_BUTTON2;
     else if (btn == 2) Fl::e_state &= ~FL_BUTTON3;
     }
     */
    if ( type == 0 ) Fl::e_state |= FL_BUTTON1;
    else if ( type == 2 ) Fl::e_state &= ~FL_BUTTON1;
    
    switch (type) {
        case 0:
            suppressed = 0;
            sendEvent = FL_PUSH;
            Fl::e_is_click = 1;
            px = (int)pos.x; py = (int)pos.y;
            if (taps > 1) Fl::e_clicks++;
            else Fl::e_clicks = 0;
            // fall through
        case 2:
            if (suppressed) {
                suppressed = 0;
                break;
            }
            //if (!window) break;
            if (!sendEvent) {
                sendEvent = FL_RELEASE;
            }
            Fl::e_keysym = keysym[btn];
            // fall through
        case 1:
            suppressed = 0;
            if (!sendEvent) {
                sendEvent = FL_MOVE;
            }
            // fall through
            /*
             case NSLeftMouseDragged:
             case NSRightMouseDragged:
             case NSOtherMouseDragged:
             */
        {
            if (suppressed) break;
            if (!sendEvent) {
                sendEvent = FL_MOVE; // Fl::handle will convert into FL_DRAG
                if (fabs(pos.x - px) > 5 || fabs(pos.y - py) > 5) Fl::e_is_click = 0;
            }
            //            mods_to_e_state(mods);
            
            //update_e_xy_and_e_xy_root([view window]);
            Fl::e_x = int(pos.x);
            Fl::e_y = int(pos.y);
            Fl::e_x_root = int(pos.x);
            Fl::e_y_root = int(pos.y);
            
            Fl::handle(sendEvent, window);
        }
            break;
        default:
            break;
    }
    
    fl_unlock_function();
    
    return;
}

//******************* spot **********************************

// public variables
CGContextRef fl_gc = 0;
void *fl_capture = 0;           // (NSWindow*) we need this to compensate for a missing(?) mouse capture
bool fl_show_iconic;                    // true if called from iconize() - shows the next created window in collapsed state
Window fl_window;
Fl_Window *Fl_Window::current_;
Fl_Fontdesc *fl_fonts = Fl_X::calc_fl_fonts();

void fl_reset_spot()
{
}

void fl_set_spot(int font, int size, int X, int Y, int W, int H, Fl_Window *win)
{
    
}

void fl_set_status(int x, int y, int w, int h)
{
}

static void FLTK_IdleTimerDisabledChanged(void *userdata, const char *name, const char *oldValue, const char *hint)
{
    BOOL disable = (hint && *hint != '0');
    [UIApplication sharedApplication].idleTimerDisabled = disable;
}

void fl_open_display()
{
	static char beenHereDoneThat = 0;

	if (beenHereDoneThat) return;
	beenHereDoneThat = 1;

	// FIXIT: do some init thing
}

// so a CGRect matches exactly what is denoted x,y,w,h for clipping purposes
CGRect fl_cgrectmake_cocoa(int x, int y, int w, int h)
{
	return CGRectMake(x, y, w > 0 ? w - 0.9 : 0, h > 0 ? h - 0.9 : 0);
}

/*
double fl_ios_flush_and_wait1(double time_to_wait) //ok
{
    Fl::flush();
    
    const CFTimeInterval sec = 0.000002;
    int result;
    do {
        result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, sec, TRUE);
    } while (result == kCFRunLoopRunHandledSource);
    
    do {
        result = CFRunLoopRunInMode((CFStringRef)UITrackingRunLoopMode, sec, TRUE);
    } while (result == kCFRunLoopRunHandledSource);
    
	return 0.0;
}
*/

double fl_ios_flush_and_wait(double time_to_wait)  //ok
{
	if ( 0 == EventPumpEnabled_ ) return 0.0;
	
    Fl::flush();
    
    //printf("start\n");
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:endDate];
    [pool release];
    //printf("runloop end\n");
    
    return 0.0;
}

void fl_clipboard_notify_change()
{
	// No need to do anything here...
}

/*
 * Check if there is actually a message pending
 */
int fl_ready() // ok
{
	return 1;
}

void Fl::enable_im()
{
    /*
    fl_open_display();
    
    im_enabled = 1;
    
    if (fl_mac_os_version >= 100500)
        [NSApp updateWindows];
    else
        im_update();
     */
    printf("fl::enable_im\n");
}

void Fl::disable_im()
{
    /*
    fl_open_display();
    
    im_enabled = 0;
    
    if (fl_mac_os_version >= 100500)
        [NSApp updateWindows];
    else
        im_update();
     */
    printf("fl::disable_im\n");
}

/*
 * smallest x coordinate in screen space of work area of menubar-containing display
 */
int Fl::x() // ok
{
	return 0;
}

/*
 * smallest y coordinate in screen space of work area of menubar-containing display
 */
int Fl::y() // ok
{
	return work_y;
}

/*
 * width of work area of menubar-containing display
 */
int Fl::w() // ok
{
	return device_w;
}

/*
 * height of work area of menubar-containing display
 */
int Fl::h() // ok
{
	return device_h-work_y;
}

// computes the work area of the nth screen (screen #0 has the menubar)
void Fl_X::screen_work_area(int &X, int &Y, int &W, int &H, int n) // ok
{
	X = 0;
	Y = 0;
	W = device_w;
	H = device_h;
}

/*
 * get the current mouse pointer world coordinates
 */
void Fl::get_mouse(int &x, int &y)
{
/*
	fl_open_display();
	NSPoint pt = [NSEvent mouseLocation];
	x = int(pt.x);
	y = int(main_screen_height - pt.y);
*/	
}


/*
 * Gets called when a window is created, resized, or deminiaturized
 */
static void handleUpdateEvent(Fl_Window *window)
{
	if (!window) return;
	Fl_X *i = Fl_X::i(window);
	i->wait_for_expose = 0;

	if (i->region) {
		XDestroyRegion(i->region);
		i->region = 0;
	}

	for (Fl_X *cx = i->xidChildren; cx; cx = cx->xidNext) {
		if (cx->region) {
			XDestroyRegion(cx->region);
			cx->region = 0;
		}
		cx->w->clear_damage(FL_DAMAGE_ALL);
        CGContextRef gc = (CGContextRef)UIGraphicsGetCurrentContext();//[[UIGraphicsPopContext currentContext] graphicsPort];
		CGContextSaveGState(gc); // save original context
		cx->flush();
		CGContextRestoreGState(gc); // restore original context
		cx->w->clear_damage();
	}
	window->clear_damage(FL_DAMAGE_ALL);
	i->flush();
	window->clear_damage();
}

void Fl_Window::fullscreen_x()
{
	_set_fullscreen();
	/* On OS X < 10.6, it is necessary to recreate the window. This is done with hide+show. */
	hide();
	show();
	Fl::handle(FL_FULLSCREEN, this);
}

void Fl_Window::fullscreen_off_x(int X, int Y, int W, int H)
{
	_clear_fullscreen();
	hide();
	resize(X, Y, W, H);
	show();
	Fl::handle(FL_FULLSCREEN, this);
}

/*
 * Initialize the given port for redraw and call the window's flush() to actually draw the content
 */
void Fl_X::flush()
{
    //*
    if (through_drawRect ) { //|| w->as_gl_window()) {
        make_current_counts = 1;
        w->flush();
        make_current_counts = 0;
        Fl_X::q_release_context();
        return;
    }
    //*/
    // have Cocoa immediately redraw the window's view
    FLView *view = (FLView *)[[fl_xid(w) rootViewController] view];
    fl_x_to_redraw = this;
    [view setNeedsDisplay];//: YES];
    // will send the drawRect: message to the window's view after having prepared the adequate NSGraphicsContext
    //[view displayIfNeededIgnoringOpacity];
    fl_x_to_redraw = NULL;
}


/*
 * go ahead, create that (sub)window
 */
void Fl_X::make(Fl_Window *w)
{
	if (w->parent()) {      // create a subwindow
		Fl_Group::current(0);
		// our subwindow needs this structure to know about its clipping.
		Fl_X *x = new Fl_X;
		x->subwindow = true;
		x->other_xid = 0;
		x->region = 0;
		x->subRegion = 0;
		x->gc = 0;          // stay 0 for Quickdraw; fill with CGContext for Quartz
		w->set_visible();
		Fl_Window *win = w->window();
		Fl_X *xo = Fl_X::i(win);
		if (xo) {
			x->xidNext = xo->xidChildren;
			x->xidChildren = 0L;
			xo->xidChildren = x;
			x->xid = win->i->xid;
			x->w = w; w->i = x;
			x->wait_for_expose = 0;
			{
				Fl_X *z = xo->next; // we don't want a subwindow in Fl_X::first
				xo->next = x;
				x->next = z;
			}
			int old_event = Fl::e_number;
			w->handle(Fl::e_number = FL_SHOW);
			Fl::e_number = old_event;
			w->redraw();      // force draw to happen
		}
		/*
		if (w->as_gl_window()) { // if creating a sub-GL-window
			while (win->window()) win = win->window();
			[Fl_X::i(win)->xid containsGLsubwindow: YES];
		}
		*/
	} else {            // create a desktop window
		Fl_Group::current(0);
		fl_open_display();

		if (w->non_modal() && Fl_X::first /*&& !fl_disable_transient_for*/) {
			// find some other window to be "transient for":
			Fl_Window *w = Fl_X::first->w;
			while (w->parent()) w = w->window(); // todo: this code does not make any sense! (w!=w??)
		}

		Fl_X *x = new Fl_X();
		x->subwindow = false;
		x->other_xid = 0; // room for doublebuffering image map. On OS X this is only used by overlay windows
		x->region = 0;
		x->subRegion = 0;
		x->xidChildren = 0;
		x->xidNext = 0;
		x->gc = 0;

		CGRect crect;
		if (w->fullscreen_active()) {
            [[UIApplication sharedApplication] setStatusBarHidden: YES];
            int sx, sy, sw, sh;
            Fl::screen_work_area(sx, sy, sw, sh);
			w->x(sx);
            w->y(sy);
			w->w(sw);
            w->h(sh);

			//w->resize(X, Y, W, H);
        } else {
            if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
                int y_ios6 = w->y();
                if (y_ios6 <= work_y) y_ios6 = 0;
                else y_ios6 -= work_y;
                w->y(y_ios6);
            }
        }
		crect.origin.x = w->x();
        crect.origin.y = w->y();
        printf("y = %f, height=%d\n", crect.origin.y, w->h());
		crect.size.width = w->w();
		crect.size.height = w->h();
		FLWindow *cw = [[FLWindow alloc] initWithFlWindow: w contentRect: crect];
        if (w->fullscreen_active()) cw.windowLevel = UIWindowLevelAlert;
        cw.opaque = YES;
        cw.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];

		x->xid = cw;
		x->w = w; w->i = x;
		x->wait_for_expose = 1;
		x->next = Fl_X::first;
		Fl_X::first = x;
        
        crect.size.width = w->w();
        crect.size.height = w->h();
        crect.origin.x = 0.0;
        crect.origin.y = 0.0;
		FLView *myview = [[FLView alloc] initWithFlWindow: w contentRect: crect];
		
		FLViewController* controller;
		controller = [[FLViewController alloc] init];
        controller.view = myview;
        cw.rootViewController = controller;
		
        myview.backgroundColor = [UIColor whiteColor];
		[cw addSubview: myview];
		[myview release];
        
        /*
        if ([controller respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
            // ios 7
            [controller prefersStatusBarHidden];
            [controller performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
        }
        */

		/*
		q_set_window_title(cw, w->label(), w->iconlabel());
		if (!w->force_position()) {
			if (w->modal()) {
				[cw center];
			} else if (w->non_modal()) {
				[cw center];
			} else {
				static NSPoint delta = NSZeroPoint;
				delta = [cw cascadeTopLeftFromPoint: delta];
			}
		}
		if (w->menu_window()) { // make menu windows slightly transparent
			[cw setAlphaValue: 0.97];
		}
		*/
		
		// Install DnD handlers
		//[myview registerForDraggedTypes: [NSArray arrayWithObjects: utf8_format,  NSFilenamesPboardType, nil]];
		/*
		if (!Fl_X::first->next) {
			// if this is the first window, we need to bring the application to the front
			[NSApp activateIgnoringOtherApps:YES];
		}
		*/

		if (w->size_range_set) w->size_range_();

		if (w->border() || (!w->modal() && !w->tooltip_window())) {
			Fl_Tooltip::enter(0);
		}

		if (w->modal()) Fl::modal_ = w;

		w->set_visible();
		if (w->border() || (!w->modal() && !w->tooltip_window())) Fl::handle(FL_FOCUS, w);
		Fl::first_window(w);
        [cw makeKeyAndVisible];

		int old_event = Fl::e_number;
		w->handle(Fl::e_number = FL_SHOW);
		Fl::e_number = old_event;

		// if (w->modal()) { Fl::modal_ = w; fl_fix_focus(); }
	}
}


/*
 * Tell the OS what window sizes we want to allow
 */
void Fl_Window::size_range_()
{
}


/*
 * returns pointer to the filename, or null if name ends with ':'
 */
const char* fl_filename_name(const char *name)
{
	const char *p, *q;
	if (!name) return (0);
	for (p = q = name; *p;) {
		if ((p[0] == ':') && (p[1] == ':')) {
			q = p + 2;
			p++;
		} else if (p[0] == '/') {
			q = p + 1;
		}
		p++;
	}
	return q;
}


/*
 * set the window title bar name
 */
void Fl_Window::label(const char *name, const char *mininame)
{
}


/*
 * make a window visible
 */
void Fl_Window::show()
{
	image(Fl::scheme_bg_);
	if (Fl::scheme_bg_) {
		labeltype(FL_NORMAL_LABEL);
		align(FL_ALIGN_CENTER | FL_ALIGN_INSIDE | FL_ALIGN_CLIP);
	} else {
		labeltype(FL_NO_LABEL);
	}
	Fl_Tooltip::exit(this);
	if (!shown()) {
		fl_open_display();
		//if (can_boxcheat(box())) fl_background_pixel = int(fl_xpixel(color()));
		Fl_X::make(this);
	} else {
		//printf("Fl_Window::show 2\n");
		// Once again, we would lose the capture if we activated the window.
		//if (IsIconic(i->xid)) OpenIcon(i->xid);
		//if (!fl_capture) BringWindowToTop(i->xid);
		//ShowWindow(i->xid,fl_capture?SW_SHOWNOACTIVATE:SW_RESTORE);
	}
}

/*
 * resize a window
 */
void Fl_Window::resize(int X, int Y, int W, int H)
{
}

// removes x,y,w,h rectangle from region r and returns result as a new Fl_Region
static Fl_Region MacRegionMinusRect(Fl_Region r, int x, int y, int w, int h)
{
    Fl_Region outr = (Fl_Region)malloc(sizeof(*outr));
    outr->rects = (CGRect *)malloc(4 * r->count * sizeof(CGRect));
    outr->count = 0;
    CGRect rect = fl_cgrectmake_cocoa(x, y, w, h);
    for (int i = 0; i < r->count; i++) {
        CGRect A = r->rects[i];
        CGRect test = CGRectIntersection(A, rect);
        if (CGRectIsEmpty(test)) {
            outr->rects[(outr->count)++] = A;
        } else {
            const CGFloat verylarge = 100000.;
            CGRect side = CGRectMake(0, 0, rect.origin.x, verylarge); // W side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(0, rect.origin.y + rect.size.height, verylarge, verylarge); // N side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(rect.origin.x + rect.size.width, 0, verylarge, verylarge); // E side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
            side = CGRectMake(0, 0, verylarge, rect.origin.y); // S side
            test = CGRectIntersection(A, side);
            if (!CGRectIsEmpty(test)) {
                outr->rects[(outr->count)++] = test;
            }
        }
    }
    if (outr->count == 0) {
        free(outr->rects);
        free(outr);
        outr = XRectangleRegion(0, 0, 0, 0);
    } else outr->rects = (CGRect *)realloc(outr->rects, outr->count * sizeof(CGRect));
    return outr;
}

void Fl_Window::make_current()
{
    if (make_current_counts > 1) return;
    if (make_current_counts) make_current_counts++;
    Fl_X::q_release_context();
    fl_window = i->xid;
    current_ = this;
    
    int xp = 0, yp = 0;
    Fl_Window *win = this;
    while (win) {
        if (!win->window()) break;
        xp += win->x();
        yp += win->y();
        win = (Fl_Window *)win->window();
    }
    i->gc = (CGContextRef)UIGraphicsGetCurrentContext();
    fl_gc = i->gc;
    Fl_Region fl_window_region = XRectangleRegion(0, 0, w(), h());
    if (!this->window()) {
        for (Fl_X *cx = i->xidChildren; cx; cx = cx->xidNext) {   // clip-out all sub-windows
            Fl_Window *cw = cx->w;
            Fl_Region from = fl_window_region;
            fl_window_region = MacRegionMinusRect(from, cw->x(), cw->y(), cw->w(), cw->h());
            XDestroyRegion(from);
        }
    }
    
    // antialiasing must be deactivated because it applies to rectangles too
    // and escapes even clipping!!!
    // it gets activated when needed (e.g., draw text)
    CGContextSetShouldAntialias(fl_gc, false);
    CGFloat hgt = [[[fl_window rootViewController] view] frame].size.height;
    //CGContextTranslateCTM(fl_gc, 0.5, hgt - 0.5f);
    CGContextTranslateCTM(fl_gc, 0.5, 0.5f);
    //CGContextScaleCTM(fl_gc, 1.0f, -1.0f); // now 0,0 is top-left point of the window
    win = this;
    while (win && win->window()) { // translate to subwindow origin if this is a subwindow context
        CGContextTranslateCTM(fl_gc, win->x(), win->y());
        win = win->window();
    }
    //apply window's clip
    CGContextClipToRects(fl_gc, fl_window_region->rects, fl_window_region->count);
    XDestroyRegion(fl_window_region);
    // this is the context with origin at top left of (sub)window clipped out of its subwindows if any
    CGContextSaveGState(fl_gc);
}

// helper function to manage the current CGContext fl_gc
extern void fl_quartz_restore_line_style_();

// FLTK has only one global graphics state. This function copies the FLTK state into the
// current Quartz context
void Fl_X::q_fill_context()
{
    if (!fl_gc) return;
    if (!fl_window) { // a bitmap context
        size_t hgt = CGBitmapContextGetHeight(fl_gc);
        CGContextTranslateCTM(fl_gc, 0.5, hgt - 0.5f);
        CGContextScaleCTM(fl_gc, 1.0f, -1.0f); // now 0,0 is top-left point of the context
    }
    fl_color(fl_graphics_driver->color());
    fl_quartz_restore_line_style_();
}

// The only way to reset clipping to its original state is to pop the current graphics
// state and restore the global state.
void Fl_X::q_clear_clipping()
{
    if (!fl_gc) return;
    CGContextRestoreGState(fl_gc);
    CGContextSaveGState(fl_gc);
}

// Give the Quartz context back to the system
void Fl_X::q_release_context(Fl_X *x)
{
    if (x && x->gc != fl_gc) return;
    if (!fl_gc) return;
    CGContextRestoreGState(fl_gc); // KEEP IT: matches the CGContextSaveGState of make_current
    CGContextFlush(fl_gc);
    fl_gc = 0;
}

void Fl_X::q_begin_image(CGRect &rect, int cx, int cy, int w, int h)
{
    CGContextSaveGState(fl_gc);
    CGRect r2 = rect;
    r2.origin.x -= 0.5f;
    r2.origin.y -= 0.5f;
    CGContextClipToRect(fl_gc, r2);
    // move graphics context to origin of vertically reversed image
    CGContextTranslateCTM(fl_gc, rect.origin.x - cx - 0.5, rect.origin.y - cy + h - 0.5);
    CGContextScaleCTM(fl_gc, 1, -1);
    rect.origin.x = rect.origin.y = 0;
    rect.size.width = w;
    rect.size.height = h;
}

void Fl_X::q_end_image()
{
    CGContextRestoreGState(fl_gc);
}

////////////////////////////////////////////////////////////////
// Copy & Paste fltk implementation.
////////////////////////////////////////////////////////////////
/*
static void convert_crlf(char *s, size_t len)
{
    // turn all \r characters into \n:
    for (size_t x = 0; x < len; x++) if (s[x] == '\r') s[x] = '\n';
}

// fltk 1.3 clipboard support constant definitions:
static NSString* calc_utf8_format(void)
{
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_6
#define NSPasteboardTypeString @"public.utf8-plain-text"
#endif
    if (fl_mac_os_version >= 100600) return NSPasteboardTypeString;
    return NSStringPboardType;
}

// clipboard variables definitions :
char *fl_selection_buffer[2] = { NULL, NULL };
int fl_selection_length[2] = { 0, 0 };
static int fl_selection_buffer_length[2];

static PasteboardRef allocatePasteboard(void)
{
    PasteboardRef clip;
    PasteboardCreate(kPasteboardClipboard, &clip); // requires Mac OS 10.3
    return clip;
}
static PasteboardRef myPasteboard = allocatePasteboard();

extern void fl_trigger_clipboard_notify(int source);

void fl_clipboard_notify_change()
{
    // No need to do anything here...
}

static void clipboard_check(void)
{
    PasteboardSyncFlags flags;
    
    flags = PasteboardSynchronize(myPasteboard); // requires Mac OS 10.3
    
    if (!(flags & kPasteboardModified)) return;
    if (flags & kPasteboardClientIsOwner) return;
    
    fl_trigger_clipboard_notify(1);
}
*/

/*
 * create a selection
 * stuff: pointer to selected data
 * len: size of selected data
 * type: always "plain/text" for now
 */
void Fl::copy(const char *stuff, int len, int clipboard, const char *type)
{
    /*
    if (!stuff || len < 0) return;
    if (len + 1 > fl_selection_buffer_length[clipboard]) {
        delete[]fl_selection_buffer[clipboard];
        fl_selection_buffer[clipboard] = new char[len + 100];
        fl_selection_buffer_length[clipboard] = len + 100;
    }
    memcpy(fl_selection_buffer[clipboard], stuff, len);
    fl_selection_buffer[clipboard][len] = 0; // needed for direct paste
    fl_selection_length[clipboard] = len;
    if (clipboard) {
        CFDataRef text = CFDataCreate(kCFAllocatorDefault, (UInt8 *)fl_selection_buffer[1], len);
        if (text == NULL) return; // there was a pb creating the object, abort.
        NSPasteboard *clip = [NSPasteboard generalPasteboard];
        [clip declareTypes: [NSArray arrayWithObject: utf8_format] owner: nil];
        [clip setData: (NSData *)text forType: utf8_format];
        CFRelease(text);
    }
     */
}

// Call this when a "paste" operation happens:
void Fl::paste(Fl_Widget &receiver, int clipboard, const char *type)
{
}

int Fl::clipboard_contains(const char *type)
{
    printf("clipboard_contains\n");
	return 0;
}

int Fl_X::unlink(Fl_X *start)
{
    if (start) {
        Fl_X *pc = start;
        while (pc) {
            if (pc->xidNext == this) {
                pc->xidNext = xidNext;
                return 1;
            }
            if (pc->xidChildren) {
                if (pc->xidChildren == this) {
                    pc->xidChildren = xidNext;
                    return 1;
                }
                if (unlink(pc->xidChildren)) return 1;
            }
            pc = pc->xidNext;
        }
    } else {
        for (Fl_X *pc = Fl_X::first; pc; pc = pc->next) {
            if (unlink(pc)) return 1;
        }
    }
    return 0;
}

void Fl_X::relink(Fl_Window *w, Fl_Window *wp)
{
    Fl_X *x = Fl_X::i(w);
    Fl_X *p = Fl_X::i(wp);
    if (!x || !p) return;
    // first, check if 'x' is already registered as a child of 'p'
    for (Fl_X *i = p->xidChildren; i; i = i->xidNext) {
        if (i == x) return;
    }
    // now add 'x' as the first child of 'p'
    x->xidNext = p->xidChildren;
    p->xidChildren = x;
}

void Fl_X::destroy()
{
    // subwindows share their xid with their parent window, so should not close it
    if (!subwindow && w && !w->parent() && xid) {
        [xid resignKeyWindow];
    }
}

void Fl_X::map()
{
    if (w && xid) {
        [xid orderFront: nil];
    }
    //+ link to window list
    if (w && w->parent()) {
        Fl_X::relink(w, w->window());
        w->redraw();
    }
}

void Fl_X::unmap()
{
    if (w && !w->parent() && xid) {
        [xid orderOut: nil];
    }
    if (w && Fl_X::i(w)) Fl_X::i(w)->unlink();
}

// intersects current and x,y,w,h rectangle and returns result as a new Fl_Region
Fl_Region Fl_X::intersect_region_and_rect(Fl_Region current, int x, int y, int w, int h)
{
    if (current == NULL) return XRectangleRegion(x, y, w, h);
    CGRect r = fl_cgrectmake_cocoa(x, y, w, h);
    Fl_Region outr = (Fl_Region)malloc(sizeof(*outr));
    outr->count = current->count;
    outr->rects = (CGRect *)malloc(outr->count * sizeof(CGRect));
    int j = 0;
    for (int i = 0; i < current->count; i++) {
        CGRect test = CGRectIntersection(current->rects[i], r);
        if (!CGRectIsEmpty(test)) outr->rects[j++] = test;
    }
    if (j) {
        outr->count = j;
        outr->rects = (CGRect *)realloc(outr->rects, outr->count * sizeof(CGRect));
    } else {
        XDestroyRegion(outr);
        outr = XRectangleRegion(0, 0, 0, 0);
    }
    return outr;
}

void Fl_X::collapse()
{
}

CFDataRef Fl_X::CGBitmapContextToTIFF(CGContextRef c)
{ 
	return (CFDataRef)0;
}

void Fl_X::set_key_window()
{
}

int Fl::dnd(void)
{
	return true;
}

/*
static NSBitmapImageRep* rect_to_NSBitmapImageRep(Fl_Window *win, int x, int y, int w, int h)
// the returned value is autoreleased
{
    CGRect rect;
    UIView *winview = nil;
    while (win->window()) {
        x += win->x();
        y += win->y();
        win = win->window();
    }
    if (through_drawRect) {
        CGFloat epsilon = 0;
        //if (fl_mac_os_version >= 100600) epsilon = 0.5; // STR #2887
        //rect = NSMakeRect(x - epsilon, y - epsilon, w, h);
        epsilon = 0.5;
    } else {
        rect = NSMakeRect(x, win->h() - (y + h), w, h);
        // lock focus to win's view
        winview = [fl_xid(win) contentView];
        [winview lockFocus];
    }
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithFocusedViewRect: rect] autorelease];
    if (!through_drawRect) [winview unlockFocus];
    return bitmap;
}
 */

unsigned char* Fl_X::bitmap_from_window_rect(Fl_Window *win, int x, int y, int w, int h, int *bytesPerPixel)
/* Returns a capture of a rectangle of a mapped window as a pre-multiplied RGBA array of bytes.
 Alpha values are always 1 (except for the angles of a window title bar)
 so pre-multiplication can be ignored. 
 *bytesPerPixel is always set to the value 4 upon return.
 delete[] the returned pointer after use
 */
{
    /*
    NSBitmapImageRep *bitmap = rect_to_NSBitmapImageRep(win, x, y, w, h);
    if (bitmap == nil) return NULL;
    *bytesPerPixel = [bitmap bitsPerPixel] / 8;
    int bpp = (int)[bitmap bytesPerPlane];
    int bpr = (int)[bitmap bytesPerRow];
    int hh = bpp / bpr; // sometimes hh = h-1 for unclear reason
    int ww = bpr / (*bytesPerPixel); // sometimes ww = w-1
    unsigned char *data = new unsigned char[w * h *  *bytesPerPixel];
    if (w == ww) {
        memcpy(data, [bitmap bitmapData], w * hh *  *bytesPerPixel);
    } else {
        unsigned char *p = [bitmap bitmapData];
        unsigned char *q = data;
        for (int i = 0; i < hh; i++) {
            memcpy(q, p, *bytesPerPixel * ww);
            p += bpr;
            q += w * *bytesPerPixel;
        }
    }
    return data;
     */
    return NULL;
}

CGImageRef Fl_X::CGImage_from_window_rect(Fl_Window *win, int x, int y, int w, int h)
// CFRelease the returned CGImageRef after use
{
	return 0;
}

Window fl_xid(const Fl_Window *w) //ok
{
	Fl_X *temp = Fl_X::i(w);
	return temp ? temp->xid : 0;
}

// no decorated border
int Fl_Window::decorated_w() //ok
{
    return w();
}

int Fl_Window::decorated_h() //ok
{
    return h();
}

// not implentment fd function in ios
void Fl::add_fd(int n, int events, void (*cb)(int, void *), void *v) //ok
{
}

void Fl::add_fd(int fd, void (*cb)(int, void *), void *v) //ok
{
}

void Fl::remove_fd(int n, int events) //ok
{
}

void Fl::remove_fd(int n) //ok
{
}

//==============================================================================
static Fl_Window::DisplayOrientation convertOrientation(UIInterfaceOrientation orientation)
{
	switch (orientation) {
	case UIInterfaceOrientationPortrait:            return Fl_Window::upright;
	case UIInterfaceOrientationPortraitUpsideDown:  return Fl_Window::upsideDown;
	case UIInterfaceOrientationLandscapeLeft:       return Fl_Window::rotatedClockwise;
	case UIInterfaceOrientationLandscapeRight:      return Fl_Window::rotatedAntiClockwise;
	default:                                        return Fl_Window::upright; // unknown orientation!
	}
	return Fl_Window::upright;
}

Fl_Window::DisplayOrientation Fl_Window::getCurrentOrientation()
{
	return convertOrientation([[UIApplication sharedApplication] statusBarOrientation]);
}

static NSUInteger getSupportedOrientations(Fl_Window *w)
{
    NSUInteger allowed = 0;

    if (w->isOrientationEnabled (Fl_Window::upright))              allowed |= UIInterfaceOrientationMaskPortrait;
    if (w->isOrientationEnabled (Fl_Window::upsideDown))           allowed |= UIInterfaceOrientationMaskPortraitUpsideDown;
    if (w->isOrientationEnabled (Fl_Window::rotatedClockwise))     allowed |= UIInterfaceOrientationMaskLandscapeLeft;
    if (w->isOrientationEnabled (Fl_Window::rotatedAntiClockwise)) allowed |= UIInterfaceOrientationMaskLandscapeRight;

    return allowed;
}

/*
static CGRect convertToCGRect (const RectType& r)
{
	return CGRectMake ((CGFloat) r.getX(), (CGFloat) r.getY(), (CGFloat) r.getWidth(), (CGFloat) r.getHeight());
}
*/

//==============================================================================
//========================== implementation ====================================
//==============================================================================
@implementation FLViewController

- (NSUInteger) supportedInterfaceOrientations
{
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
    return getSupportedOrientations(w);
}

- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation
{
	FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
    return w->isOrientationEnabled (convertOrientation(interfaceOrientation));
}

- (void) willRotateToInterfaceOrientation: (UIInterfaceOrientation) toInterfaceOrientation duration: (NSTimeInterval) duration
{
    (void) toInterfaceOrientation;
    (void) duration;

    [UIView setAnimationsEnabled: NO]; // disable this because it goes the wrong way and looks like crap.
}

- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation
{
    (void) fromInterfaceOrientation;

	//FLView *view = (FLView *)[self view];
	//Fl_Window *w = [view getFl_Window];
	/*
    JuceUIView* juceView = (JuceUIView*) [self view];
    jassert (juceView != nil && juceView->owner != nullptr);
    juceView->owner->updateTransformAndScreenBounds();
	*/

    [UIView setAnimationsEnabled: YES];
}

- (BOOL)prefersStatusBarHidden
{
    printf("prefersStatusBarHidden\n");
    FLView *view = (FLView *)[self view];
	Fl_Window *w = [view getFl_Window];
    if ( w->fullscreen_active() ) return YES;
    else {
        printf("no\n");
        return NO;
    }
}
@end

@implementation FLView

- (FLView*) initWithFlWindow: (Fl_Window*)win contentRect: (CGRect) rect;
{
    [super initWithFrame: rect];
	
	flwindow = win;

    hiddenTextView = [[UITextView alloc] initWithFrame: CGRectZero];
    [self addSubview: hiddenTextView];
    hiddenTextView.delegate = self;

    hiddenTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    hiddenTextView.autocorrectionType = UITextAutocorrectionTypeNo;

    return self;
}

- (Fl_Window *)getFl_Window
{
	return flwindow;
}

- (void) dealloc
{
    [hiddenTextView removeFromSuperview];
    [hiddenTextView release];

    [super dealloc];
}

//==============================================================================
- (void) drawRect: (CGRect) r
{
    //if (owner != nullptr) owner->drawRect (r);
	
	fl_lock_function();
	through_drawRect = YES;
	if (fl_x_to_redraw) fl_x_to_redraw->flush();
	else handleUpdateEvent(flwindow);
	through_drawRect = NO;
	fl_unlock_function();
}

//==============================================================================
- (void) touchesBegan: (NSSet*) touches withEvent: (UIEvent*) event
{
    (void) touches;

    //if (owner != nullptr)
    //    owner->handleTouches (event, true, false, false);
}

- (void) touchesMoved: (NSSet*) touches withEvent: (UIEvent*) event
{
    (void) touches;

    //if (owner != nullptr)
    //    owner->handleTouches (event, false, false, false);
}

- (void) touchesEnded: (NSSet*) touches withEvent: (UIEvent*) event
{
    (void) touches;

    //if (owner != nullptr)
    //    owner->handleTouches (event, false, true, false);
}

- (void) touchesCancelled: (NSSet*) touches withEvent: (UIEvent*) event
{
    //if (owner != nullptr)
    //    owner->handleTouches (event, false, true, true);

    [self touchesEnded: touches withEvent: event];
}

//==============================================================================
- (BOOL) becomeFirstResponder
{
    //if (owner != nullptr)
    //    owner->viewFocusGain();

    return true;
}

- (BOOL) resignFirstResponder
{
    //if (owner != nullptr)
    //    owner->viewFocusLoss();

    return true;
}

- (BOOL) canBecomeFirstResponder
{
    //return owner != nullptr && owner->canBecomeKeyWindow();
	return true;
}

- (BOOL) textView: (UITextView*) textView shouldChangeTextInRange: (NSRange) range replacementText: (NSString*) text
{
    (void) textView;
    //return owner->textViewReplaceCharacters (Range<int> ((int) range.location, (int) (range.location + range.length)), nsStringToJuce (text));
	// FIXIT:
	return NO;
}

@end

//==============================================================================
@implementation FLWindow
- (FLWindow *)initWithFlWindow: (Fl_Window *)flw contentRect: (CGRect)rect
{
    self = [super initWithFrame: rect];
    if (self) w = flw;
    return self;
}
- (Fl_Window *)getFl_Window
{
    return w;
}

- (void) becomeKeyWindow;
{
	[super becomeKeyWindow];
	
	[self makeKeyWindow];
	
	// FIXIT: save focus current uiwindow?
}
@end

#endif // __FLTK_IPHONEOS__
