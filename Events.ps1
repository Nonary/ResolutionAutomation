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


function Join-Overrides($width, $height, $refresh) {
    Write-Debug "Function Join-Overrides called with Width: $width, Height: $height, Refresh: $refresh"

    Write-Host "Before Overriding: $width x $height x $refresh"

    foreach ($override in $settings.overrides) {
        Write-Debug "Checking override with client width: $($override.client.width), height: $($override.client.height), refresh: $($override.client.refresh)"
        if ($override.client.width -eq $width -and $override.client.height -eq $height -and $override.client.refresh -eq $refresh) {
            Write-Debug "Match found. Overriding with host width: $($override.host.width), height: $($override.host.height), refresh: $($override.host.refresh)"
            $width = $override.host.width
            $height = $override.host.height
            $refresh = $override.host.refresh
            break
        }
    }

    Write-Host "After Overriding: $width x $height x $refresh"

    return @{
        Width   = $width
        Height  = $height
        Refresh = $refresh
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