param($terminate)
Set-Location (Split-Path $MyInvocation.MyCommand.Path -Parent)

Add-Type -Path .\internals\DisplaySettings.cs

# If reverting the resolution fails, you can set a manual override here.
$host_resolution_override = @{
    Width   = 0
    Height  = 0
    Refresh = 0
}

## Code and type generated with ChatGPT v4, 1st prompt worked flawlessly.
Function Set-ScreenResolution($width, $height, $frequency) { 
    Write-Host "Setting screen resolution to $width x $height x $frequency"
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
                Write-Host "Failed to change resolution. Error code: $result"
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
            Width   = $devMode.dmPelsWidth
            Height  = $devMode.dmPelsHeight
            Refresh = $devMode.dmDisplayFrequency
        }
    }
}
function Assert-ResolutionChange($width, $height, $refresh) {
    # Attempt to set the resolution up to 6 times, in event of failures
    for ($i = 0; $i -lt 12; $i++) {
        $hostResolution = Get-HostResolution
        $refreshDiff = [Math]::Abs($hostResolution.Refresh - $refresh)
        if (($width -ne $hostResolution.Width) -or ($height -ne $hostResolution.Height) -or ($refreshDiff -ge 2)) {
            # If the resolutions don't match, set the screen resolution to the current client's resolution
            Write-Host "Current Resolution: $($hostResolution.Width) x $($hostResolution.Height) x $($hostResolution.Refresh)"
            Write-Host "Expected Requested Resolution: $width x $height x $refresh"
            Set-ScreenResolution $width $height $refresh
        }
        # Wait for a while before checking the resolution again
        Start-Sleep -Milliseconds 500
    }
}


function Join-Overrides($width, $height, $refresh) {
    $overrides = Get-Content ".\overrides.txt" -ErrorAction SilentlyContinue
    Write-Host "Overrides loaded: $overrides"
    foreach ($line in $overrides) {
        if ($null -ne $line -and "" -ne $line) {
            $overrides = $line | Select-String "(?<width>\d{1,})x(?<height>\d*)x?(?<refresh>\d*)?" -AllMatches
    
            $heights = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'height' }
            $widths = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'width' }
            $refreshes = $overrides[0].Matches.Groups | Where-Object { $_.Name -eq 'refresh' }

            if ($widths[0].Value -eq $width -and $heights[0].Value -eq $height -and $refreshes[0].Value -eq $refresh) {
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
}



function IsCurrentlyStreaming() {
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

function OnStreamStart($width, $height, $refresh) {
    $expectedRes = Join-Overrides -width $width -height $height -refresh $refresh
    Set-ScreenResolution -Width $expectedRes.Width -Height $expectedRes.Height -Freq $expectedRes.Refresh
    Assert-ResolutionChange -width $expectedRes.Width -height $expectedRes.Height -refresh $expectedRes.Refresh
}

function OnStreamEnd($hostResolution) {

    if (($host_resolution_override.Values | Measure-Object -Sum).Sum -gt 1000) {
        $hostResolution = @{
            Width   = $host_resolution_override['Width']
            Height  = $host_resolution_override['Height']
            Refresh = $host_resolution_override['Refresh']
        }
    }
    Set-ScreenResolution -Width $hostResolution.Width -Height $hostResolution.Height -Freq $hostResolution.Refresh   
}

    

if ($terminate) {
    Stop-ResolutionMatcherScript | Out-Null
}
