/*
These structs are required, in order to handle some parameters returned from the
MultiTouchSupport.framework
*/
typedef struct {
  float x;
  float y;
} mtPoint;

typedef struct {
  mtPoint position;
  mtPoint velocity;
} mtReadout;

/*
Some reversed engineered informations from MultiTouchSupport.framework
*/
typedef struct
{
  int frame; //the current frame
  double timestamp; //event timestamp
  int identifier; //identifier guaranteed unique for life of touch per device
  int state; // Touch states, see explanation in enum below
  int unknown1; //no idea what this does
  int unknown2; //no idea what this does either
  mtReadout normalized; //the normalized position and vector of the touch (0,0 to 1,1)
  float size; //the size of the touch (the area of your finger being tracked)
  int unknown3; //no idea what this does
  float angle; //the angle of the touch -|
  float majorAxis; //the major axis of the touch -|-- an ellipsoid. you can track the angle of each finger!
  float minorAxis; //the minor axis of the touch -|
  mtReadout unknown4; //not sure what this is for
  int unknown5[2]; //no clue
  float unknown6; //no clue
} Touch;

//a reference pointer for the multitouch device
typedef void *MTDeviceRef;

//the prototype for the callback function
typedef int (*MTContactCallbackFunction)(int,Touch*,int,double,int);

//returns a pointer to the default device (the trackpad?)
MTDeviceRef MTDeviceCreateDefault();

//returns a CFMutableArrayRef array of all multitouch devices
CFMutableArrayRef MTDeviceCreateList(void);

//registers a device's frame callback to your callback function
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);

// Possible touch states
enum {
  MTTouchStateNotTracking = 0,
  MTTouchStateStartInRange = 1,
  MTTouchStateHoverInRange = 2,
  MTTouchStateMakeTouch = 3,
  MTTouchStateTouching = 4,
  MTTouchStateBreakTouch = 5,
  MTTouchStateLingerInRange = 6,
  MTTouchStateOutOfRange = 7
};

