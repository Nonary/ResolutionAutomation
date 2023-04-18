param($terminate)
$path = "Insert Path Here, or Run the Install_as_Precommand.ps1 file"

Set-Location $path

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplaySettings {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct DEVMODE {
        private const int CCHDEVICENAME = 32;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
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
    }
}
"@

## Code and type generated with ChatGPT v4, 1st prompt worked flawlessly.
Function Set-ScreenResolution($width, $height, $frequency) { 
    $tolerance = 2 # Set the tolerance value for the frequency comparison
    $devMode = New-Object DisplaySettings+DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)
    $modeNum = 0

    while ([DisplaySettings]::EnumDisplaySettings([NullString]::Value, $modeNum, [ref]$devMode)) {
        $frequencyDiff = [Math]::Abs($devMode.dmDisplayFrequency - $frequency)
        if ($devMode.dmPelsWidth -eq $width -and $devMode.dmPelsHeight -eq $height -and $frequencyDiff -le $tolerance) {
            $result = [DisplaySettings]::ChangeDisplaySettings([ref]$devMode, 0)
            if ($result -eq 0) {
                Write-Host "Resolution changed successfully."
            }
            else {
                throw "Failed to change resolution. Error code: $result"
            }
            break
        }
        $modeNum++
    }
}


function Get-ClientResolution() {
    $log_path = "$env:WINDIR\Temp\sunshine.log" 

    # Initialize a hash table to store the client resolution values
    $clientRes = @{
        Height = 0
        Width  = 0
        Refresh = 0
    }

    # Define regular expressions to match the height, width, and refresh rate values in the log file
    $widthRegex = [regex] "a=x-nv-video\[0\]\.clientViewportWd:(\d+)"
    $heightRegex = [regex] "a=x-nv-video\[0\]\.clientViewportHt:(\d+)"
    $hzRegex = [regex] "a=x-nv-video\[0\]\.maxFPS:(?<hz>\d+)"

    # Read the log file into an array of strings, split by newlines
    $lines = Get-Content $log_path -ReadCount 0 | ForEach-Object { $_ -split "`n" }
    
    # Iterate through the array of strings in reverse order
    for ($i = $lines.Length - 1; $i -ge 0; $i--) {
        # Get the current line as a string
        [string]$line = $lines[$i]

        # Skip to the next line if the line doesn't start with "a=x"
        # This is a performance optimization, this will match much faster than regular expressions.
        if(-not $line.StartsWith("a=x")){
            continue;
        }

        # Attempt to match the height value in the line
        if ($clientRes.Height -eq 0) {
            $clientResMatch = $heightRegex.Match($line)
            if ($clientResMatch.Success) {
                $clientRes.Height = [int]$clientResMatch.Groups[1].Value
            }
        }

        # Attempt to match the width value in the line
        if ($clientRes.Width -eq 0) {
            $clientResMatch = $widthRegex.Match($line)
            if ($clientResMatch.Success) {
                $clientRes.Width = [int]$clientResMatch.Groups[1].Value
            }
        }

        # Attempt to match the refresh rate value in the line
        if ($clientRes.Refresh -eq 0) {
            $clientRefreshMatch = $hzRegex.Match($line)
            if ($clientRefreshMatch.Success) {
                $clientRes.Refresh = [int]$clientRefreshMatch.Groups[1].Value
            }
        }

        # Exit the loop if all three values have been found
        if ($clientRes.Height -gt 0 -and $clientRes.Width -gt 0 -and $clientRes.Refresh -gt 0) {
            break
    }
    }

    return $clientRes
}

function Apply-Overrides($resolution) {

    $overrides = Get-Content "$path\overrides.txt" -ErrorAction SilentlyContinue
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
    return $null -ne (Get-NetUDPEndpoint -OwningProcess (Get-Process sunshine).Id -ErrorAction Ignore)
}



function Stop-ResolutionMatcherScript() {

    $pipeExists = Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -eq "ResolutionMatcher" } 
    if ($pipeExists.Length -gt 0) {
        $pipeName = "ResolutionMatcher"
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::Out)
        $pipe.Connect()
        $streamWriter = New-Object System.IO.StreamWriter($pipe)
        $streamWriter.WriteLine("Terminate")
        try {
            $streamWriter.Flush()
            $streamWriter.Dispose()
            $pipe.Dispose()
        }
        catch {
            # We don't care if the disposal fails, this is common with async pipes.
            # Also, this powershell script will terminate anyway.
        }
    }
}

function OnStreamStart() {
    $resolution = Apply-Overrides -resolution (Get-ClientResolution)
    Write-Host "Attempting to set resolution to the following values"
    $resolution
    Set-ScreenResolution -Width $resolution.width -Height $resolution.height -Freq $resolution.refresh
}

function OnStreamEnd($hostResolutions) {

    foreach ($resolution in $hostResolutions) {
        try {
            Write-Host "Attempting to set resolution to the following values"
            $resolution
            Set-ScreenResolution -Width $resolution.CurrentHorizontalResolution -Height $resolution.CurrentVerticalResolution -Freq $resolution.CurrentRefreshRate
            break;
        }
        catch {
            Write-Host "Failed to set resolution, will attempt to try again if there are any leftover resolutions"
        }
    }

}
    

if ($terminate) {
    Stop-ResolutionMatcherScript | Out-Null
}
