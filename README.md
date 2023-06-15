## Host Resolution Matching for Moonlight Streaming

This script changes your host resolution to match exactly with Moonlight's resolution. This is mostly used for users who have different aspect ratios between the client and host, or anyone who wishes to match the resolution while streaming.

### Requirements

#### For Sunshine Users
- Host must be Windows.
- Sunshine must be installed as a service (it does not work with the zip version of Sunshine).
- Sunshine logging level must be set to Debug.
- Users must have read permissions to `%WINDIR%/Temp/Sunshine.log` (do not change other permissions, just make sure Users has at least read permissions).

### Caveats
 - If using Windows 11, you'll need to set the default terminal to Windows Console Host as there is currently a bug in Windows Terminal that prevents hidden consoles from working properly.
    * That can be changed at Settings > Privacy & security > Security > For developers > Terminal [Let Windows decide] >> (change to) >> Terminal [Windows Console Host]
 - Prepcommands do not work from cold reboots, and will prevent Sunshine from working until you logon locally.
   * You should add a new application (with any name you'd like) in the WebUI and leave **both** the command and detached command empty.
   * When adding this new application, make sure global prep command option is disabled.
   * That will serve as a fallback option when you have to remote into your computer from a cold start.
   * Normal reboots issued from start menu, will still work without the workaround above as long as Settings > Accounts > Sign-in options and "Use my sign-in info to automatically finish setting up after an update" is enabled which is default in Windows 10 & 11.
 - The script will stop working if you move the folder, simply reinstall it to resolve that issue.

#### GFE Users
- Unsupported.

### Installation Instructions
1. Store the downloaded folder in a location you intend to keep. If you delete this folder or move it, the automation will stop working.
2. To install, double click the Install.bat file.
3. To uninstall, double click the Uninstall.bat file.

This script will ask for elevated rights because in the coming future, Sunshine configuration will be locked from modifications for non-administrator users.

### How it Works
1. When you start streaming any application in Sunshine, it will start the script.
2. The script reads the `Sunshine.log` file to capture Moonlight's resolution.
3. It sets the host's resolution to match the Moonlight resolution (including refresh rate), unless overridden with the `overrides` file.
4. The script waits for Sunshine to be suspended for more than 120 seconds or until the user ends the stream.
5. It sets the host resolution back to the same resolution it was prior to starting the stream (including refresh rate).

This will only work if the resolution is available to be used, so you will need to make sure to use NVIDIA Custom Resolution or CRU to add the client resolution first.

### Overrides File
You may have a mobile device that you wish to stream at a lower resolution to save bandwidth or some devices may perform better when streaming at a lower resolution. If you want your host to change the resolution to something higher than the client, use the `overrides` file to do this.

#### Format
```
WidthxHeightxRefresh=WidthxHeightxRefresh
```

The resolution on the left is what triggers the override, and the one on the right is what the host will be set to.

#### Example
To stream at 720p and keep the host at 4k resolution, you would add this line:
```
1280x700x60=3840x2160x60
```