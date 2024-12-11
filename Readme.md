## Host Resolution Matching for Moonlight Streaming

This script changes your host resolution to match exactly with Moonlight's resolution. This is mostly used for users who have different aspect ratios between the client and host, or anyone who wishes to match the resolution while streaming.

### Requirements

- Host must be Windows.
- Sunshine 0.21.0 or higher

### Caveats:
 - If using Windows 11, you'll need to set the default terminal to Windows Console Host as there is currently a bug in Windows Terminal that prevents hidden consoles from working properly.
    * That can be changed at Settings > System > For Developers > Terminal [Let Windows decide] >> (change to) >> Terminal [Windows Console Host]
    * On older versions of Windows 11 it can be found at: Settings > Privacy & security > Security > For developers > Terminal [Let Windows decide] >> (change to) >> Terminal [Windows Console Host]
 - The script will stop working if you move the folder, simply reinstall it to resolve that issue.
 - Due to Windows API restrictions, this script does not work on cold reboots (hard crashes or shutdowns of your computer).
    * If you're cold booting, simply sign into the computer using the "Desktop" app on Moonlight, then end the stream, then start it again. 

#### GFE Users
- You'll need to use the Geforce Experience version of this script instead. 
  - The current release for Geforce Experience users is: https://github.com/Nonary/ResolutionAutomation/releases/tag/2.0.15_gfe

### Installation Instructions
1. Store the downloaded folder in a location you intend to keep. If you delete this folder or move it, the automation will stop working.
2. To install, double click the Install.bat file.
3. To uninstall, double click the Uninstall.bat file.

This script will ask for elevated rights because Sunshine configuration is be locked from modifications for non-administrator users.

### How it Works
1. When you start streaming any application in Sunshine, it will start the script.
2. The script reads the environment variables passed to it via Sunshine, which contains client information such as screen resolution.
3. It sets the host's resolution to match the Moonlight resolution (including refresh rate), unless overridden with the `overrides` file.
4. The script waits for Sunshine to be suspended for more than 120 seconds or until the user ends the stream.
5. It sets the host resolution back to the same resolution it was prior to starting the stream (including refresh rate).

This will only work if the resolution is available to be used, so you will need to make sure to use NVIDIA Custom Resolution or CRU to add the client resolution first.

### Overrides (Setting)
You may have a mobile device that you wish to stream at a lower resolution to save bandwidth or some devices may perform better when streaming at a lower resolution. If you want your host to change the resolution to something higher than the client, make modifications to the overrides section in the settings.json file

#### Format
```
WidthxHeightxRefresh=WidthxHeightxRefresh
```

The resolution on the left is what triggers the override, and the one on the right is what the host will be set to.

#### Example
To stream at 720p and keep the host at 4k resolution, you would add this line:
```
"overrides": [
        // recommended for steam deck users, uncomment to enable, but make sure you have 3840x2400 added on your host!
        // sunshine has issues downscaling to smaller resolutions, so it is recommended to stream above native (you will see a significant difference)
        // simply uncomment below line once done
        //"2560x1440x90=3840x2400x60",
        "1280x720x60=3840x2160x60"
    ]
```
