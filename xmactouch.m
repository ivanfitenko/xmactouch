#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h> // NSWorkspace sleep/wake notifications
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h> // kVK_ANSI_*
#include <sys/time.h> // gettimeofday
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <stdatomic.h>

#include "multitouch.h" // required to use MultiTouchSupport.framework

// The trackpad's multitouch HID service gets torn down and recreated across
// a sleep/wake cycle, which silently invalidates the device refs we grabbed
// at launch (no crash, the callback just stops firing). We re-run device
// discovery on wake to pick up whatever refs are current. The driver may not
// be ready the instant the wake notification fires, so retry a few times.
#define MULTITOUCH_RECONNECT_MAX_ATTEMPTS 5
#define MULTITOUCH_RECONNECT_RETRY_SECONDS 1.0

// touchCallback runs on a MultitouchSupport-owned background thread, while
// mouseCallback runs on the main thread via the CGEventTap run loop; the
// flag they share needs to be atomic so a write on one thread is guaranteed
// visible before the posted event it precedes is processed on the other.
#define RIGHT_MOUSE_BUTTON_REAL 0
#define RIGHT_MOUSE_BUTTON_GENERATED 1

char isDragging = 0;
long long prevClickTime = 0;
long long curClickTime = 0;

CGEventTapLocation tapA = kCGAnnotatedSessionEventTap;
CGEventTapLocation tapH = kCGHIDEventTap;

// Status flag for tripple tap
enum {
  trippleClickPending = 0,
  trippleClickSent = 1,
  trippleClickCleared = 2
};
int trippleClickStatus = 2;

#define DOUBLE_CLICK_MILLIS 500

long long now() {
  struct timeval te;
  gettimeofday( & te, NULL );
  long long milliseconds = te.tv_sec*1000LL + te.tv_usec/1000; // caculate milliseconds
  return milliseconds;
}

// Flag to indicate either original right-click or the one generated here.
_Atomic int rightMouseButtonEventSource = RIGHT_MOUSE_BUTTON_REAL;

//start sending events
void MTDeviceStart(MTDeviceRef, int);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);

int touchCallback(int device, Touch *data, int nFingers, double timestamp, int frame);

static void connectMultitouchDevicesAttempt(int attemptsLeft) {
  NSArray *deviceList = (NSArray*)MTDeviceCreateList();
  NSUInteger count = [deviceList count];

  if (count == 0 && attemptsLeft > 0) {
    // Commented-out debugging output. Maybe enable it later with cli option?
    //printf("xmactouch: no multitouch devices found, retrying (%d attempts left)\n", attemptsLeft);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(MULTITOUCH_RECONNECT_RETRY_SECONDS * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
      connectMultitouchDevicesAttempt(attemptsLeft - 1);
    });
    return;
  }

  for (NSUInteger i = 0; i < count; i++) {
    MTDeviceRef device = (MTDeviceRef)[deviceList objectAtIndex:i];
    // Unregister first in case this device ref survived the sleep cycle and
    // is already registered, so we don't end up with duplicate callbacks.
    MTUnregisterContactFrameCallback(device, touchCallback);
    MTRegisterContactFrameCallback(device, touchCallback);
    MTDeviceStart(device, 0);
  }
  // Commented-out debugging output. Maybe enable it later with cli option?
  //printf("xmactouch: connected %lu multitouch device(s)\n", (unsigned long)count);
}

// Human-readable Touch.state, for debug logging only.
static const char* touchStateName(int state) {
  switch (state) {
    case MTTouchStateNotTracking:   return "NotTracking";
    case MTTouchStateStartInRange:  return "StartInRange";
    case MTTouchStateHoverInRange:  return "HoverInRange";
    case MTTouchStateMakeTouch:     return "MakeTouch";
    case MTTouchStateTouching:      return "Touching";
    case MTTouchStateBreakTouch:    return "BreakTouch";
    case MTTouchStateLingerInRange: return "LingerInRange";
    case MTTouchStateOutOfRange:    return "OutOfRange";
    default:                        return "Unknown";
  }
}

//just output debug info. use it to see all the raw infos dumped to screen
void printDebugInfos(int nFingers, Touch *data, int briefMode) {
  int i;

  for (i=0; i<nFingers; i++) {
    Touch *f = &data[i];
    if (briefMode) {
      printf("Finger: %d, state: %d (%s)\n",
             i,
             f->state, touchStateName(f->state));
    } else {
      printf("Finger: %d, frame: %d, timestamp: %f, ID: %d, state: %d (%s), PosX: %f, PosY: %f, VelX: %f, VelY: %f, Angle: %f, MajorAxis: %f, MinorAxis: %f\n", i,
             f->frame,
             f->timestamp,
             f->identifier,
             f->state, touchStateName(f->state),
             f->normalized.position.x,
             f->normalized.position.y,
             f->normalized.velocity.x,
             f->normalized.velocity.y,
             f->angle,
             f->majorAxis,
             f->minorAxis);
      }
    }
}

// this's a simple touchCallBack routine. handle your events here
int touchCallback(int device, Touch *data, int nFingers, double timestamp, int frame) {
  int i;

  // Commented-out debugging output. Maybe enable it later with cli option?
  //if (nFingers >= 1) {
  //  printf("[%lld] touchCallback Device: %d nFingers: %d\n", now(), device, nFingers);
  //  printDebugInfos(nFingers, data, 0);
  //}

  if (nFingers == 3) {
    // Releasing any of three fingers sends Tripple Click. Only arm it from
    // Cleared, so that the other two fingers' own release events (landing
    // in later frames of the same gesture, while nFingers is still 3)
    // don't trigger a duplicate click.
    if (trippleClickStatus == trippleClickCleared &&
        (data[0].state == MTTouchStateBreakTouch ||
         data[1].state == MTTouchStateBreakTouch ||
         data[2].state == MTTouchStateBreakTouch)) {
      trippleClickStatus = trippleClickSent;
    }

    if (trippleClickStatus == trippleClickSent) {
      // Commented-out debugging output. Maybe enable it later with cli option?
      //printf("[%lld] Three-finger tap detected\n", now());

      //Get current mouse coorinates
      CGEventRef dummyEvent = CGEventCreate(nil);
      CGPoint mouseLocationSnap = CGEventGetLocation(dummyEvent);
      CFRelease(dummyEvent);

      //Generate right mouse click
      CGEventRef mouseClickDown = CGEventCreateMouseEvent(
        NULL, kCGEventRightMouseDown, mouseLocationSnap, kCGMouseButtonRight );
      CGEventRef mouseClickUp = CGEventCreateMouseEvent(
        NULL, kCGEventRightMouseUp, mouseLocationSnap, kCGMouseButtonRight );
      CGEventPost( tapH, mouseClickDown );
      CGEventPost( tapH, mouseClickUp );
      CFRelease( mouseClickDown );
      CFRelease( mouseClickUp );
      trippleClickStatus = trippleClickPending;
      // set a flag to indicate that this is a re-mapped event and does not
      // need further remapping
      rightMouseButtonEventSource = RIGHT_MOUSE_BUTTON_GENERATED;
    }
  } else if (trippleClickStatus != trippleClickCleared) {
    // Fewer than three fingers touching means any three-finger gesture has
    // fully ended, however its release happened to be split across frames.
    // Re-arm here instead of waiting for another BreakTouch frame at
    // nFingers==3 that may never come - relying on that was the bug: a tap
    // whose three fingers all released within a single frame left no such
    // frame to re-arm on, silently swallowing the next three-finger tap.
    trippleClickStatus = trippleClickCleared;
  }
return 0;
}

static void paste(CGEventRef event) {

  // Paste.
  CGEventSourceRef source = CGEventSourceCreate( kCGEventSourceStateCombinedSessionState );
  CGEventRef kbdEventPasteDown = CGEventCreateKeyboardEvent( source, kVK_ANSI_V, 1 );
  CGEventRef kbdEventPasteUp   = CGEventCreateKeyboardEvent( source, kVK_ANSI_V, 0 );
  CGEventSetFlags( kbdEventPasteDown, kCGEventFlagMaskCommand );
  CGEventPost( tapA, kbdEventPasteDown );
  CGEventPost( tapA, kbdEventPasteUp );
  CFRelease( kbdEventPasteDown );
  CFRelease( kbdEventPasteUp );

  CFRelease( source );

  // Generate middle click.
  CGPoint mouseLocationMiddle = CGEventGetLocation( event );
  CGEventRef mouseClickDownMiddle = CGEventCreateMouseEvent(
    NULL, kCGEventOtherMouseDown, mouseLocationMiddle, kCGMouseButtonCenter );
  CGEventRef mouseClickUpMiddle   = CGEventCreateMouseEvent(
    NULL, kCGEventOtherMouseUp,   mouseLocationMiddle, kCGMouseButtonCenter );
  CGEventPost( tapH, mouseClickDownMiddle );
  CGEventPost( tapH, mouseClickUpMiddle );
  CFRelease( mouseClickDownMiddle );
  CFRelease( mouseClickUpMiddle );

}

static void copy() {
  CGEventSourceRef source = CGEventSourceCreate( kCGEventSourceStateCombinedSessionState );
  CGEventRef kbdEventDown = CGEventCreateKeyboardEvent( source, kVK_ANSI_C, 1 );
  CGEventRef kbdEventUp   = CGEventCreateKeyboardEvent( source, kVK_ANSI_C, 0 );
  CGEventSetFlags( kbdEventDown, kCGEventFlagMaskCommand );
  CGEventPost( tapA, kbdEventDown );
  CGEventPost( tapA, kbdEventUp );
  CFRelease( kbdEventDown );
  CFRelease( kbdEventUp );
  CFRelease( source );
}

static void recordClickTime() {
  prevClickTime = curClickTime;
  curClickTime = now();
}

static char isDoubleClickSpeed() {
  return ( curClickTime - prevClickTime ) < DOUBLE_CLICK_MILLIS;
}

static char isDoubleClick() {
  return isDoubleClickSpeed();
}

static CGEventRef mouseCallback (CGEventTapProxy proxy,
                                 CGEventType type, CGEventRef event,
                                 void * refcon) {

  // Commented-out debugging output. Maybe enable it later with cli option?
  //printf("[%lld] mouseCallback type: %d rightMouseButtonEventSource: %d\n",
  //       now(), type, rightMouseButtonEventSource);

  switch (type) {
    case kCGEventRightMouseDown:
      // RightMouseButton clicks generated by our remapping handler will be
      // left intact. "Real" right clicks will be remapped to middle clicks,
      // plus "cmd-v" keyboard event will be sent to paste from buffer.
      if (rightMouseButtonEventSource == RIGHT_MOUSE_BUTTON_GENERATED) {
        // done processing remapped right click, reset generated flag
        rightMouseButtonEventSource = RIGHT_MOUSE_BUTTON_REAL;
        // Give a user 0.05 seconds to raise all fingers, otherwise middle
        // click events could be generated. Unfortunately, this might break
        // some of double-clicks with three fingers, but that would be a
        // horrible excersize itself, and I hope you don't have to do it.
        usleep(50000);
      } else {
        paste(event);
        // Drop the original right mouse tap event, we sent a middle button
        return 0;
      }
      break;

    case kCGEventLeftMouseDown:
      recordClickTime();
      break;

    case kCGEventLeftMouseUp:
      if (isDoubleClick() || isDragging) {
        copy();
      }
      isDragging = 0;
      break;

    case kCGEventLeftMouseDragged:
      isDragging = 1;
      break;

    default:
      break;
    }

  // Return unmodified original event by default
  return event;
}

int main (int argc, char ** argv) {
  CGEventMask emask;
  CFMachPortRef myEventTap;
  CFRunLoopSourceRef eventTapRLSrc;
  // EXAMPLE: sample variable passable to callback, could be anything because it
  // will be consumed by void*
  int var_for_callback = 42;

  // Unbuffered, so debug output shows up immediately even when stdout is
  // redirected to a file instead of a terminal.
  setbuf(stdout, NULL);

  // connect multitouch devices
  connectMultitouchDevicesAttempt(MULTITOUCH_RECONNECT_MAX_ATTEMPTS);

  // The trackpad's multitouch device gets re-enumerated across sleep/wake,
  // which invalidates the refs grabbed above. Re-run discovery on wake so
  // two/three-finger gestures keep working after the laptop sleeps.
  [[[NSWorkspace sharedWorkspace] notificationCenter]
    addObserverForName:NSWorkspaceDidWakeNotification
                object:nil
                 queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
              connectMultitouchDevicesAttempt(MULTITOUCH_RECONNECT_MAX_ATTEMPTS);
            }];

  // We want "other" mouse button click-release, such as middle or exotic,
  // plus two "regular" buttons, left and right/secondary.
  emask = CGEventMaskBit(kCGEventOtherMouseDown) |
          CGEventMaskBit(kCGEventRightMouseDown) |
          CGEventMaskBit(kCGEventLeftMouseDown) |
          CGEventMaskBit(kCGEventLeftMouseUp) |
          CGEventMaskBit(kCGEventLeftMouseDragged);

  // Create the Tap
  myEventTap = CGEventTapCreate (kCGSessionEventTap, // Catch all events for current user session
                                  kCGTailAppendEventTap, // Append to end of EventTap list
                                  kCGEventTapOptionDefault, // We only listen, we don't modify
                                  emask, // event mask as set above
                                  & mouseCallback, // our callback function defined in this file
                                  & var_for_callback // a way to pass user to callback
                                  );
  if (!myEventTap) {
    printf("Error: CGEventTapCreate failed. Make sure that the application itself\n");
    printf("and an application used to launch it (e.g. Terminal) are allowed under\n");
    printf("System Settings -> Privacy & Security -> Accessibility.\n");
    return(13);
  }

  // Create a RunLoop Source for it
  eventTapRLSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, myEventTap, 0);

  // Add the source to the current RunLoop
  CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRLSrc, kCFRunLoopDefaultMode);

  // Keep the RunLoop running forever
  CFRunLoopRun();

  // Not reached (RunLoop above never stops running)
  return 0;
}
