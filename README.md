
## xmactouch - xorg-style copy and paste with a trackpad on Mac

### About

This tool intends to make your Macbook trackpad act the same as it would on Linux with Xorg. You can copy the text to the clipboard by simply highlighting (selecting) it (no ctrl-v), and then paste it with two finger tap, which now once again means the middle button - and yes, it's not only about pasting it, two-finger tap is also a middle button for all your apps now. And the right click is remapped to a three-finger tap where we Linux guys always expect it to be on our touchpads.

### Features (the above, in normal language):

* Middle click is now available for Mac's touchpad, and is assigned to a 2-finger tap

* Copy text to buffer by highlighting it (selecting it with the mouse cursor)

* Paste text with a middle click, which in our case (Mac's touchpad) is assigned to a 2-finger tap

* Right-click is assigned to a three-finger tap, just like it is on Linux-based laptops

#### If you use a mouse:

There is a different tool for you. Please try [macpaste](https://github.com/lodestone/macpaste) , and it will give you all the same features (actually, xmactouch could be considered a heavily modified version of macpaste intended to work with touchpads instead of mice.) I think xmacpaste wouldn't work for you... unless you know exactly what you are doing, of course.

### Running xmactouch:
1. Enable right click if you didn't do so yet. Go to "System Preferences" -> "Trackpad", and check the box next to "Secondary Click".
2. Disable Mac’s Look Up which is assigned to three-finger tap. Go to "System Preferences" -> "Trackpad", and uncheck the box next to "Look up & data detectors", or switch the binding to "Force Click with one finger"
3. Build the binary by running `make` command in source code directory.
4. Add permissions for xmactouch and the terminal you use to launch it to "System Settings -> Privacy & Security -> Accessibility".
5. Run the binary with `./xmactouch` in source code directory, or move it whenever you want and run it from there - the further actions are up to you.

### Acknowlegdements:
This tool is based on [macpaste](https://github.com/lodestone/macpaste), with Multitouch-related headers and guidelines found at http://www.iphonesmartapps.org/aladino/?a=multitouch
### License:
Public domain, see LICENSE
### Disclaimer:
I understand that there is a ton of dubious and outright ugly solutions here in the source code. Please do not blame me. The other systems allow you a click-through way of setting such things, so I was ready to put only that much effort into that code. Sorry. PRs are welcome.
