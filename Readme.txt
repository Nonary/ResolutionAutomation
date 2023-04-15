ELI5: Changes your host resolution to match exactly with Moonlight's resolution.
Why: Mostly used for users who have different aspect ratios between the client and host. 
Or anyone that wishes to match the resolution while streaming.


Requirements:

For Sunshine Users
    Host must be Windows
    Sunshine must be installed a service (it does not work with the zip version of Sunshine)
    Sunshine logging level must be set to Debug
    Users must have read permissions to %WINDIR%/Temp/Sunshine.log (do not change other permissions, just make sure Users has atleast read permisisons)

GFE Users:
	Unsupported.

Install instructions:
    First, store this folder in a location you intend to keep. If you delete this folder or move it, the automation will stop working.
    If you have to move the folder, move it, then run the installation script again.

    To install, simply right click the Install_as_Precommand.ps1 file and select Run With Powershell.
    To uninstall, do the same thing with Uninstall_as_Precommand.ps1

    This script will ask for elevated rights, because in the coming future Sunshine configuration will be locked from modifications for non-administrator users.

How it works:

    1. When you start streaming any application in Sunshine, it will start the script.
    2. Reads Sunshine.log file to capture moonlights resolution.
    3. Sets the hosts resolution to match the Moonlight resolution (including refresh rate), unless overrided with the eoverrides file.
    4. Waits for Sunshine to be suspended for more than 120 seconds, or until the user ends the stream.
    5. Sets the host resolution back to the same resolution it was prior to starting the stream (including refresh rate).


This will only work if the resolution is available to be used, so you will need to make sure to use NVIDIA Custom Resolution or CRU to add the client resolution first.

Overrides File:
  You may have a mobile device that you wish to stream at a lower resolution to save bandwidth
  Or, some devices may perform better when streaming at a lower resolution.

  If you want your host to change the resolution to something higher than the client, use the overrides file to do this.

  Format:  WidthxHeightxRefresh=WidthxHeightxRefresh
  
  Resolution on the left is what triggers the override, the one on the right is what the host will be set to.

  For example, to stream at 720p and keep the host at 4k resolution you would add this line:
    1280x700x60=3840x2160x60

