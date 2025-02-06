# Determine the path of the currently running script and set the working directory to that path
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
. .\Helpers.ps1 -n $scriptName
Add-Type -Path .\internals\DisplaySettings.cs

# Load settings from a JSON file located in the same directory as the script
$settings = Get-Settings

# Initialize a script scoped dictionary to store variables.
# This dictionary is used to pass parameters to functions that might not have direct access to script scope, like background jobs.
if (-not $script:arguments) {
    $script:arguments = @{}
}

# Function to execute at the start of a stream
function OnStreamStart() {
    # Store the original resolution of the host machine, so it can be restored later
    $script:arguments['original_resolution'] = Get-HostResolution
    $expectedRes = Join-Overrides -width $env:SUNSHINE_CLIENT_WIDTH -height $env:SUNSHINE_CLIENT_HEIGHT -refresh $env:SUNSHINE_CLIENT_FPS
    $expectedRes = Set-10bitCompatibilityIfApplicable -width $expectedRes.Width -height $expectedRes.Height -refresh $expectedRes.Refresh
    # If highest refresh rate is enabled in settings, override the refresh rate with the highest available
    if ($settings.preferHighestRefreshRate -eq $true) {
        $highest = Get-HighestRefreshRateForResolution $expectedRes.Width $expectedRes.Height
        Write-Host "Highest refresh rate enabled. Overriding refresh rate to $highest."
        $expectedRes.Refresh = $highest
    }
    Set-ScreenResolution -Width $expectedRes.Width -Height $expectedRes.Height -Freq $expectedRes.Refresh
    Assert-ResolutionChange -width $expectedRes.Width -height $expectedRes.Height -refresh $expectedRes.Refresh
}

# Function to execute at the end of a stream. This function is called in a background job,
# and hence doesn't have direct access to the script scope. $kwargs is passed explicitly to emulate script:arguments.
function OnStreamEnd($kwargs) {
    Write-Debug "Function OnStreamEnd called with kwargs: $kwargs"

    $originalResolution = $kwargs['original_resolution']
    Write-Debug "Original resolution: $originalResolution"

    if ($settings.preferredResolution.enabled) {
        Write-Debug "Preferred resolution is enabled"
        $originalResolution = @{
            Width   = $settings.preferredResolution.width
            Height  = $settings.preferredResolution.height
            Refresh = $settings.preferredResolution.refresh
        }
        Write-Debug "New original resolution: $originalResolution"
    }

    Set-ScreenResolution -Width $originalResolution.Width -Height $originalResolution.Height -Freq $originalResolution.Refresh   
    Write-Debug "Screen resolution set to: $($originalResolution.Width) x $($originalResolution.Height) x $($originalResolution.Refresh)"

    return $true
}




Function Set-ScreenResolution($width, $height, $frequency) { 
    Write-Debug "Function Set-ScreenResolution called with Width: $width, Height: $height, Frequency: $frequency"
    Write-Host "Setting screen resolution to $width x $height x $frequency"
    $tolerance = 2 # Set the tolerance value for the frequency comparison
    Write-Debug "Tolerance: $tolerance"
    $devMode = New-Object DisplaySettings+DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)
    Write-Debug "devMode.dmSize: $($devMode.dmSize)"
    $modeNum = 0

    while ([DisplaySettings]::EnumDisplaySettings([NullString]::Value, $modeNum, [ref]$devMode)) {
        Write-Debug "Current modeNum: $modeNum"
        Write-Debug "Current devMode.dmPelsWidth: $($devMode.dmPelsWidth)"
        Write-Debug "Current devMode.dmPelsHeight: $($devMode.dmPelsHeight)"
        Write-Debug "Current devMode.dmDisplayFrequency: $($devMode.dmDisplayFrequency)"
        $frequencyDiff = [Math]::Abs($devMode.dmDisplayFrequency - $frequency)
        Write-Debug "Frequency difference: $frequencyDiff"
        if ($devMode.dmPelsWidth -eq $width -and $devMode.dmPelsHeight -eq $height -and $frequencyDiff -le $tolerance) {
            Write-Debug "Match found. Attempting to change resolution."
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
    Write-Debug "Function Get-HostResolution called"

    $devMode = New-Object DisplaySettings+DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)
    Write-Debug "devMode.dmSize: $($devMode.dmSize)"

    $modeNum = -1

    while ([DisplaySettings]::EnumDisplaySettings([NullString]::Value, $modeNum, [ref]$devMode)) {
        Write-Debug "Current modeNum: $modeNum"
        Write-Debug "Current devMode.dmPelsWidth: $($devMode.dmPelsWidth)"
        Write-Debug "Current devMode.dmPelsHeight: $($devMode.dmPelsHeight)"
        Write-Debug "Current devMode.dmDisplayFrequency: $($devMode.dmDisplayFrequency)"

        return @{
            Width   = $devMode.dmPelsWidth
            Height  = $devMode.dmPelsHeight
            Refresh = $devMode.dmDisplayFrequency
        }
    }
}
function Assert-ResolutionChange($width, $height, $refresh) {
    Write-Debug "Function Assert-ResolutionChange called with Width: $width, Height: $height, Refresh: $refresh"

    # Attempt to set the resolution up to 6 times, in event of failures
    for ($i = 0; $i -lt 12; $i++) {
        Write-Debug "Attempt number: $($i + 1)"
        $hostResolution = Get-HostResolution
        Write-Debug "Current host resolution: $($hostResolution.Width) x $($hostResolution.Height) x $($hostResolution.Refresh)"
        $refreshDiff = [Math]::Abs($hostResolution.Refresh - $refresh)
        Write-Debug "Refresh difference: $refreshDiff"
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


function Join-Overrides {
    param (
        [int]$Width,
        [int]$Height,
        [int]$Refresh
    )

    Write-Debug "Function Join-Overrides called with Width: $Width, Height: $Height, Refresh: $Refresh"

    Write-Host "Before Overriding: $Width x $Height x $Refresh"

    # Initialize variables to hold the best matching override
    $matchedOverride = $null
    $matchedSpecificity = -1  # Higher value means more specific

    foreach ($override in $settings.overrides) {
        Write-Debug "Processing override: $override"

        # Split the override into client and host parts
        $parts = $override -split '='
        if ($parts.Count -ne 2) {
            Write-Warning "Invalid override format (missing '='): $override"
            continue
        }

        $clientPart = $parts[0].Trim()
        $hostPart = $parts[1].Trim()

        # Function to parse a dimension string into a hashtable
        function Parse-Dimension {
            param (
                [string]$dimensionStr
            )
            $dimParts = $dimensionStr -split 'x'
            if ($dimParts.Count -lt 2 -or $dimParts.Count -gt 3) {
                return $null
            }

            $parsed = @{
                Width   = [int]$dimParts[0]
                Height  = [int]$dimParts[1]
                Refresh = if ($dimParts.Count -eq 3) { [int]$dimParts[2] } else { $null }
            }
            return $parsed
        }

        # Parse client and host dimensions
        $client = Parse-Dimension -dimensionStr $clientPart
        $host_res = Parse-Dimension -dimensionStr $hostPart

        if (-not $client -or -not $host_res) {
            Write-Warning "Invalid dimension format in override: $override"
            continue
        }

        Write-Debug "Parsed Client: Width=$($client.Width), Height=$($client.Height), Refresh=$($client.Refresh)"
        Write-Debug "Parsed Host: Width=$($host_res.Width), Height=$($host_res.Height), Refresh=$($host_res.Refresh)"

        # Check if the client dimensions match the input dimensions
        if ($client.Width -eq $Width -and $client.Height -eq $Height) {
            # Determine specificity: 2 if both width/height and refresh match,
            # 1 if only width and height match, 0 otherwise
            $specificity = 1
            if ($null -ne $client.Refresh) {
                if ($client.Refresh -eq $Refresh) {
                    $specificity = 2
                } else {
                    # Refresh specified in override but does not match input
                    continue
                }
            }

            Write-Debug "Override specificity: $specificity"

            # Select the override with the highest specificity
            if ($specificity -gt $matchedSpecificity) {
                $matchedOverride = $host_res
                $matchedSpecificity = $specificity
                Write-Debug "Selected override: $override with specificity $specificity"
            }
        }
    }

    # Apply the matched override if any
    if ($null -ne $matchedOverride) {
        Write-Debug "Applying override: Width=$($matchedOverride.Width), Height=$($matchedOverride.Height), Refresh=$($matchedOverride.Refresh)"
        $Width = $matchedOverride.Width
        $Height = $matchedOverride.Height
        if ($null -ne $matchedOverride.Refresh) {
            $Refresh = $matchedOverride.Refresh
        }
    } else {
        Write-Debug "No matching override found."
    }

    Write-Host "After Overriding: $Width x $Height x $Refresh"

    return @{
        Width   = $Width
        Height  = $Height
        Refresh = $Refresh
    }
}


function Set-10bitCompatibilityIfApplicable($width, $height, $refresh) {
    Write-Debug "Function Set-10bitCompatibilityIfApplicable called with Width: $width, Height: $height, Refresh: $refresh"
    Write-Debug "SUNSHINE_CLIENT_HDR environment variable: $($env:SUNSHINE_CLIENT_HDR)"

    # We only need to care about 10-bit compatibility if the resolution is higher than 1440p
    if (($width -gt 2560 -and $height -gt 1440) -or ($width -gt 1440 -and $height -gt 2560)) {
        Write-Debug "Resolution is higher than 1440p"
        if ($env:SUNSHINE_CLIENT_HDR -and $settings.force10BitDepthOnUnsupportedDevices.enabled) {
            Write-Debug "SUNSHINE_CLIENT_HDR is set and force10BitDepthOnUnsupportedDevices is enabled"
            $refresh = $settings.force10BitDepthOnUnsupportedDevices.refreshRate
            Write-Debug "New Refresh rate set to: $refresh"
            Write-Host "Forcing refresh rate to $refresh for 10-bit compatibility on dummy plugs!"
        }
    }
    else {
        Write-Debug "Resolution is not higher than 1440p, therefore we do not need to care about 10-bit compatibility."
    }

    Write-Debug "Returning Width: $width, Height: $height, Refresh: $refresh"
    return @{
        Width   = $width
        Height  = $height
        Refresh = $refresh
    }
}

function Get-HighestRefreshRateForResolution($width, $height) {
    Write-Debug "Function Get-HighestRefreshRateForResolution called with Width: $width, Height: $height"
    $highestRefresh = 0
    $modeNum = 0
    $devMode = New-Object DisplaySettings+DEVMODE
    $devMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($devMode)
    while ([DisplaySettings]::EnumDisplaySettings([NullString]::Value, $modeNum, [ref]$devMode)) {
        if (($devMode.dmPelsWidth -eq $width) -and ($devMode.dmPelsHeight -eq $height)) {
            if ($devMode.dmDisplayFrequency -gt $highestRefresh) {
                $highestRefresh = $devMode.dmDisplayFrequency
            }
        }
        $modeNum++
    }
    Write-Debug "Highest refresh rate for resolution $width x $height is $highestRefresh"
    return $highestRefresh
}