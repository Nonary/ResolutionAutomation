param($terminate)
Set-Location (Split-Path $MyInvocation.MyCommand.Path -Parent)

Add-Type -Path .\internals\DisplaySettings.cs
Add-Type -Path .\internals\OptimizedLogReader.cs

# If reverting the resolution fails, you can set a manual override here.
$host_resolution_override = @{
    Width   = 0
    Height  = 0
    Refresh = 0
}

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

function Get-HostResolution {
    $devMode = New-Object DisplaySettings+DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)
    $modeNum = -1

    while ([DisplaySettings]::EnumDisplaySettings([NullString]::Value, $modeNum, [ref]$devMode)) {
        return @{
            CurrentHorizontalResolution = $devMode.dmPelsWidth
            CurrentVerticalResolution   = $devMode.dmPelsHeight
            CurrentRefreshRate          = $devMode.dmDisplayFrequency
        }
    }
}

function Assert-ResolutionChange($original) {
    for ($i = 0; $i -lt 20; $i++) {
        $currentRes = Join-Overrides -resolution (Get-ClientResolution)
        if (($currentRes.Width -ne $original.Width) -or ($currentRes.Height -ne $original.Height) -or ($currentRes.Refresh -ne $original.Refresh)) {
            # If the resolutions don't match, set the screen resolution to the current client's resolution
            Write-Host "The client resolution changed within the past 6 seconds, this implies the first time the resolution was changed may have been incorrect due to stale data"

            Set-ScreenResolution $currentRes.Width $currentRes.Height $currentRes.Refresh
            # Exit the loop after setting the resolution
            break
        }
        # Wait for a while before checking the resolution again
        Start-Sleep -Milliseconds 500
    }
}

function Get-ClientResolution() {
    $log_path = "$env:WINDIR\Temp\sunshine.log" 

    # Initialize a hash table to store the client resolution values
    $currentRes = @{
        Height  = 0
        Width   = 0
        Refresh = 0
    }

    # Define combined regular expressions to match the height, width, and refresh rate values in the log file
    $regex = [regex] "a=x-nv-video\[0\]\.(clientViewportWd:(?<wd>\d+)|clientViewportHt:(?<ht>\d+)|maxFPS:(?<hz>\d+))"

    $reader = New-Object ReverseFileReader -ArgumentList $log_path

    while ($null -ne ($line = $reader.ReadLine())) {
        # Skip to the next line if the line doesn't start with "a=x"
        # This is a performance optimization, this will match much faster than regular expressions.
        if (-not $line.StartsWith("a=x")) {
            continue;
        }

        # Attempt to match the values in the line
        $match = $regex.Match($line)

        if ($match.Success) {
            if ($currentRes.Height -eq 0 -and $match.Groups['ht'].Success) {
                $currentRes.Height = [int]$match.Groups['ht'].Value
            }

            if ($currentRes.Width -eq 0 -and $match.Groups['wd'].Success) {
                $currentRes.Width = [int]$match.Groups['wd'].Value
            }

            if ($currentRes.Refresh -eq 0 -and $match.Groups['hz'].Success) {
                $currentRes.Refresh = [int]$match.Groups['hz'].Value
            }

            # Exit the loop if all three values have been found
            if ($currentRes.Height -gt 0 -and $currentRes.Width -gt 0 -and $currentRes.Refresh -gt 0) {
                break;
            }
        }
    }

    $reader.Dispose()

    return $currentRes
}




function Join-Overrides($resolution) {

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
    return $null -ne (Get-NetUDPEndpoint -OwningProcess (Get-Process sunshine).Id -ErrorAction Ignore)
}



function Stop-ResolutionMatcherScript() {

    $pipeExists = Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -eq "ResolutionMatcher" } 
    if ($pipeExists.Length -gt 0) {
        $pipeName = "ResolutionMatcher"
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::Out)
        $pipe.Connect(5)
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
    $expectedRes = Join-Overrides -resolution (Get-ClientResolution)
    Write-Host "Attempting to set resolution to the following values"
    $expectedRes
    Set-ScreenResolution -Width 1920 -Height 1080 -Freq 120
    Assert-ResolutionChange -resolution $expectedRes
}

function OnStreamEnd($hostResolution) {

    if (($host_resolution_override.Values | Measure-Object -Sum).Sum -gt 1000) {
        $hostResolution = @{
            CurrentHorizontalResolution = $host_resolution_override['Width']
            CurrentVerticalResolution   = $host_resolution_override['Height']
            CurrentRefreshRate          = $host_resolution_override['Refresh']
        }
    }
    Write-Host "Attempting to set resolution to the following values"
    $hostResolution
    Set-ScreenResolution -Width $hostResolution.CurrentHorizontalResolution -Height $hostResolution.CurrentVerticalResolution -Freq $hostResolution.CurrentRefreshRate   
}

    

if ($terminate) {
    Stop-ResolutionMatcherScript | Out-Null
}
