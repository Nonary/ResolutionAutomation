
Function Set-ScreenResolution { 
 
    <# 
    .Synopsis 
        Sets the Screen Resolution of the primary monitor 
    .Description 
        Uses Pinvoke and ChangeDisplaySettings Win32API to make the change 
    .Example 
        Set-ScreenResolution -Width 1024 -Height 768    -Freq 60         
    #> 
    param ( 
        [Parameter(Mandatory = $true, 
            Position = 0)] 
        [int] 
        $Width, 
 
        [Parameter(Mandatory = $true, 
            Position = 1)] 
        [int] 
        $Height, 

        [Parameter(Mandatory = $true, 
            Position = 2)] 
        [int] 
        $Freq
    ) 
 
    $pinvokeCode = @" 
 
using System; 
using System.Runtime.InteropServices; 
 
namespace Resolution 
{ 
 
    [StructLayout(LayoutKind.Sequential)] 
    public struct DEVMODE1 
    { 
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] 
        public string dmDeviceName; 
        public short dmSpecVersion; 
        public short dmDriverVersion; 
        public short dmSize; 
        public short dmDriverExtra; 
        public int dmFields; 
 
        public short dmOrientation; 
        public short dmPaperSize; 
        public short dmPaperLength; 
        public short dmPaperWidth; 
 
        public short dmScale; 
        public short dmCopies; 
        public short dmDefaultSource; 
        public short dmPrintQuality; 
        public short dmColor; 
        public short dmDuplex; 
        public short dmYResolution; 
        public short dmTTOption; 
        public short dmCollate; 
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] 
        public string dmFormName; 
        public short dmLogPixels; 
        public short dmBitsPerPel; 
        public int dmPelsWidth; 
        public int dmPelsHeight; 
 
        public int dmDisplayFlags; 
        public int dmDisplayFrequency; 
 
        public int dmICMMethod; 
        public int dmICMIntent; 
        public int dmMediaType; 
        public int dmDitherType; 
        public int dmReserved1; 
        public int dmReserved2; 
 
        public int dmPanningWidth; 
        public int dmPanningHeight; 
    }; 
 
 
 
    class User_32 
    { 
        [DllImport("user32.dll")] 
        public static extern int EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE1 devMode); 
        [DllImport("user32.dll")] 
        public static extern int ChangeDisplaySettings(ref DEVMODE1 devMode, int flags); 
 
        public const int ENUM_CURRENT_SETTINGS = -1; 
        public const int CDS_UPDATEREGISTRY = 0x01; 
        public const int CDS_TEST = 0x02; 
        public const int DISP_CHANGE_SUCCESSFUL = 0; 
        public const int DISP_CHANGE_RESTART = 1; 
        public const int DISP_CHANGE_FAILED = -1; 
    } 
 
 
 
    public class PrmaryScreenResolution 
    { 
        static public string ChangeResolution(int width, int height, int freq) 
        { 
 
            DEVMODE1 dm = GetDevMode1(); 
 
            if (0 != User_32.EnumDisplaySettings(null, User_32.ENUM_CURRENT_SETTINGS, ref dm)) 
            { 
 
                dm.dmPelsWidth = width; 
                dm.dmPelsHeight = height; 
                dm.dmDisplayFrequency = freq;
 
                int iRet = User_32.ChangeDisplaySettings(ref dm, User_32.CDS_TEST); 
 
                if (iRet == User_32.DISP_CHANGE_FAILED) 
                { 
                    return "Unable to process your request. Sorry for this inconvenience."; 
                } 
                else 
                { 
                    iRet = User_32.ChangeDisplaySettings(ref dm, User_32.CDS_UPDATEREGISTRY); 
                    switch (iRet) 
                    { 
                        case User_32.DISP_CHANGE_SUCCESSFUL: 
                            { 
                                return "Success"; 
                            } 
                        case User_32.DISP_CHANGE_RESTART: 
                            { 
                                return "You need to reboot for the change to happen.\n If you feel any problems after rebooting your machine\nThen try to change resolution in Safe Mode."; 
                            } 
                        default: 
                            { 
                                return "Failed to change the resolution, code: " + iRet; 
                            } 
                    } 
 
                } 
 
 
            } 
            else 
            { 
                return "Failed to change the resolution."; 
            } 
        } 
 
        private static DEVMODE1 GetDevMode1() 
        { 
            DEVMODE1 dm = new DEVMODE1(); 
            dm.dmDeviceName = new String(new char[32]); 
            dm.dmFormName = new String(new char[32]); 
            dm.dmSize = (short)Marshal.SizeOf(dm); 
            return dm; 
        } 
    } 
} 
 
"@ 
 
    Add-Type $pinvokeCode -ErrorAction SilentlyContinue 
    [Resolution.PrmaryScreenResolution]::ChangeResolution($width, $height, $freq) 
}

function IsSunshineUser() {
    return $null -ne (Get-Process sunshine -ErrorAction SilentlyContinue)
}

function Get-ClientResolution() {
    $log_path = If (IsSunshineUser) { "$env:WINDIR\Temp\sunshine.log" } Else { "$env:ProgramData\NVIDIA Corporation\NvStream\NvStreamerCurrent.log" }
    $log_text = Get-Content  $log_path
    $clientRes = $log_text | Select-String "video\[0\]\.clientViewport.*:\s?(?<res>\d+)" | Select-Object matches -ExpandProperty matches -Last 2
    $clientRefresh = $log_text | Select-String "video\[0\]\.maxFPS:\s?(?<hz>\d+)" | Select-Object matches -ExpandProperty matches -Last 1

    [int]$client_width = $clientRes[0].Groups['res'].Value
    [int]$client_height = $clientRes[1].Groups['res'].Value
    [int]$client_hz = $clientRefresh[0].Groups['hz'].Value

    return @{
        width   = $client_width
        height  = $client_height
        refresh = $client_hz
    }
}

function Apply-Overrides($resolution) {

    $overrides = Get-Content ".\overrides.txt" -ErrorAction SilentlyContinue
    $width = $resolution.width
    $height = $resolution.height
    $refresh = $resolution.refresh

    foreach ($line in $overrides) {
        $overrides = $line | Select-String "(?<width>\d{1,})x(?<height>\d*)x?(?<refresh>\d*)?" -AllMatches

        $heights = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'height' }
        $widths = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'width' }
        $refreshes = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'refresh' }

        if ($widths[0].Value -eq $resolution.width -and $heights[0].Value -eq $resolution.height -and $refreshes[0].Value -eq $resolution.refresh) {
            $width = $widths[1].Value
            $height = $heights[1].Value
            $refresh = $refreshes[1].Value
            break
        }
    }

    return @{
        height  = $height
        width   = $width
        refresh = $refresh
    }


}



function UserIsStreaming() {
    if (IsSunshineUser) {
        return $null -ne (Get-NetUDPEndpoint -OwningProcess (Get-Process sunshine).Id -ErrorAction Ignore)
    }

    return $null -ne (Get-Process nvstreamer -ErrorAction SilentlyContinue)
}



$lastStreamed = [System.DateTime]::MinValue
$hostResolution = Get-CimInstance -ClassName Win32_videocontroller  |  Where-Object {$_.CurrentRefreshRate -gt 0 -and $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } | Select-Object CurrentRefreshRate, CurrentHorizontalResolution, CurrentVerticalResolution -First 1
$onStreamEventTriggered = $false
while ($true) {
    $delaySettings = if (IsSunshineUser) { [pscustomobject]@{StartDelay = 1; EndDelay = 1; } } Else { [pscustomobject]@{StartDelay = 8; EndDelay = 0 } }
    if (UserIsStreaming) {
        $lastStreamed = Get-Date
        if (!$onStreamEventTriggered) {
            # Capture host resolution again, in case it changed recently.
            $hostResolution = Get-CimInstance -ClassName Win32_videocontroller  |  Where-Object {$_.CurrentRefreshRate -gt 0 -and $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } | Select-Object CurrentRefreshRate, CurrentHorizontalResolution, CurrentVerticalResolution -First 1
            Start-Sleep -Seconds $delaySettings.StartDelay
            $resolution = Apply-Overrides -resolution (Get-ClientResolution)
            Set-ScreenResolution -Width $resolution.width -Height $resolution.height -Freq $resolution.refresh
            $onStreamEventTriggered = $true
        }

    }
    elseif ($onStreamEventTriggered -and ((Get-Date) - $lastStreamed).TotalSeconds -gt $delaySettings.EndDelay) {
        Set-ScreenResolution -Width $hostResolution.CurrentHorizontalResolution -Height $hostResolution.CurrentVerticalResolution -Freq $hostResolution.CurrentRefreshRate
        $onStreamEventTriggered = $false
        
    }
    Start-Sleep -Seconds 1
}