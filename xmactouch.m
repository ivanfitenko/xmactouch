#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h> // kVK_ANSI_*
#include <sys/time.h> // gettimeofday
#include <unistd.h>

#include "multitouch.h" // required to use MultiTouchSupport.framework

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

// Flags to indicate either original right-click or the one generated here.
int realRightMouseButton = 0;
int generatedRightMouseButton = 1;
int *rightMouseButtonEventSource = &realRightMouseButton;

//start sending events
void MTDeviceStart(MTDeviceRef, int);

//just output debug info. use it to see all the raw infos dumped to screen
void printDebugInfos(int nFingers, Touch *data, int briefMode) {
  int i;

  for (i=0; i<nFingers; i++) {
    Touch *f = &data[i];
    if (briefMode) {
      printf("Finger: %d, state: %d\n",
             i,
             f->state);
    } else {
      printf("Finger: %d, frame: %d, timestamp: %f, ID: %d, state: %d, PosX: %f, PosY: %f, VelX: %f, VelY: %f, Angle: %f, MajorAxis: %f, MinorAxis: %f\n", i,
             f->frame,
             f->timestamp,
             f->identifier,
             f->state,
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

  if (nFingers >= 2) { //only report if two or more fingers are touching
    // Commented-out debugging output. Maybe enable it later with cli option?
    //printf("Device: %d ",device);
    //printf("nFingers: %d ", nFingers);
    //printDebugInfos(nFingers, data, 0);

    if (nFingers == 3) {
      // Releasing any of three fingers sends Tripple Click
      if (data[0].state == MTTouchStateBreakTouch ||
          data[1].state == MTTouchStateBreakTouch ||
          data[2].state == MTTouchStateBreakTouch) {
        if (trippleClickStatus == trippleClickCleared) {
          trippleClickStatus = trippleClickSent;
        // When click was already sent, releasing other fingers should not
        // trigger new (duplicate) tripple clicks
        } else {
          trippleClickStatus = trippleClickCleared;
        }
      }

      if (trippleClickStatus == trippleClickSent) {
        // Commented-out debugging output. Maybe enable it later with cli option?
        //printf("Three-finger tap detected\n");

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
        // Stop processing "fade out" events to avoid treating any to possible
        // subsequent events "LingerInRange" and "OutOfRange" as new events.
        // We cannot just presizely aim at "MTTouchStateBreakTouch" event here
        // because it is not always generated, so we need this filtering logics
        // to react to the release-related event and then skip subsequent ones.
        trippleClickStatus = trippleClickPending;
        // set a flag to indicate that this is a re-mapped event and does not
        // need further remapping
        rightMouseButtonEventSource = &generatedRightMouseButton;
      }
    }
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

  switch (type) {
    case kCGEventRightMouseDown:
      // RightMouseButton clicks generated by our remapping handler will be
      // left intact. "Real" right clicks will be remapped to middle clicks,
      // plus "cmd-v" keyboard event will be sent to paste from buffer.
      if (*rightMouseButtonEventSource == 1) {
        // done processing remapped right click, reset generated flag
        rightMouseButtonEventSource = &realRightMouseButton;
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
  int deviceIndex;
  CGEventMask emask;
  CFMachPortRef myEventTap;
  CFRunLoopSourceRef eventTapRLSrc;
  NSMutableArray* deviceList;
  // EXAMPLE: sample variable passable to callback, could be anything because it
  // will be consumed by void*
  int var_for_callback = 42;

  // connect multitouch devices
  deviceList = (NSMutableArray*)MTDeviceCreateList(); //grab our device list
  for (deviceIndex = 0; deviceIndex<[deviceList count]; deviceIndex++) { 
    //iterate over available devices
    MTRegisterContactFrameCallback([deviceList objectAtIndex:deviceIndex],
                                    touchCallback); //assign callback for device
    MTDeviceStart([deviceList objectAtIndex:deviceIndex], 0); //start sending events
  }

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
