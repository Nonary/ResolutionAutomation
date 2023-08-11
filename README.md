## Note
This version is meant exclusively for GeForce Experience users, if you're using Sunshine please download the latest release by clicking the link below instead.

https://github.com/Nonary/ResolutionAutomation/releases/latest



# ELI5
Changes your host resolution to match exactly with Moonlight's resolution.

# Why
The biggest use case for matching resolution is for people with different aspect ratios on the client and host, such as Steam Deck and Widescreen Users.
If you do not match the resolution/aspect ratio, it will either squish or stretch the stream and or letterbox... or in some cases both!
This can also be used to supersample games on client device (such as streaming 1080p and keeping host at 4k).


# Requirements

## GFE Users
None, should work "out of the box"

# Install instructions
First, store this folder in a location you intend to keep. If you delete this folder or move it, the automation will stop working.

If you have to move the folder, move it, then run the installation script again.

To install, simply double click the Install Script.bat file.

To uninstall, simply double click the Uninstall Script.bat file.

If you get a SmartScreen warning, tell it to proceed anyway, this will only happen once.

# How it works

1. Waits for NVStreamer process to be launched if GFE, otherwise it waits for a connection from Sunshine.
2. Reads the NVStreamerCurrentLog.txt or Sunshine.log file to capture the hosts resolution and moonlights resolution.
3. Sets the hosts resolution to match the Moonlight resolution (including refresh rate).
4. Waits for NVStreamer Process to end or Sunshine connection to either suspend or terminate.
5. Sets the host resolution back to the same resolution it was prior to starting the stream (including refresh rate).


This will only work if the resolution is available to be used, so you will need to make sure to use NVIDIA Custom Resolution or CRU to add the client resolution first.

# Overrides File
You may have a mobile device that you wish to stream at a lower resolution to save bandwidth.

Or, some devices may perform better when streaming at a lower resolution.

If you want your host to change the resolution to something higher than the client, use the overrides file to do this.

```
Format:  WidthxHeightxRefresh=WidthxHeightxRefresh
```
  
Resolution on the left is what triggers the override, the one on the right is what the host will be set to.

For example, to stream at 720p and keep the host at 4k resolution you would add this line:
```
1280x700x60=3840x2160x60
```

