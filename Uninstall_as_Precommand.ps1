param($scriptPath)



# This script modifies the global_prep_cmd setting in the Sunshine configuration file
# to add a command that runs ResolutionMatcher.ps1

# Check if the current user has administrator privileges
$isAdmin = [bool]([System.Security.Principal.WindowsIdentity]::GetCurrent().groups -match 'S-1-5-32-544')

# If the current user is not an administrator, re-launch the script with elevated privileges
# if (-not $isAdmin) {
#     Start-Process powershell.exe  -Verb RunAs -ArgumentList "-NoExit -File `"$($MyInvocation.MyCommand.Path)`" `"$(Join-Path -Path (Get-Location) -ChildPath "ResolutionMatcher.ps1")`" $($MyInvocation.MyCommand.UnboundArguments)"
#     exit
# }

Write-Host $scriptPath

# Define the path to the Sunshine configuration file
$confPath = "C:\Program Files\Sunshine\config\sunshine.conf"





# Get the current value of global_prep_cmd from the configuration file
function Get-GlobalPrepCommand {
    param (
        # The path to the configuration file
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    # Read the contents of the configuration file into an array of strings
    $config = Get-Content -Path $ConfigPath

    # Find the line that contains the global_prep_cmd setting
    $globalPrepCmdLine = $config | Where-Object { $_ -match '^global_prep_cmd\s*=' }

    # Extract the current value of global_prep_cmd
    if ($globalPrepCmdLine -match '=\s*(.+)$') {
        return $matches[1]
    }
    else {
        Write-Information "Unable to extract current value of global_prep_cmd, this probably means user has not setup prep commands yet."
        return [object[]]@()
    }
}

# Remove any existing commands that contain ResolutionMatcher from the global_prep_cmd value
function Remove-ResolutionMatcherCommand {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    if ($InputObject.do -notlike "*ResolutionMatcher*") {
        return $InputObject
    }

}

# Set a new value for global_prep_cmd in the configuration file
function Set-GlobalPrepCommand {
    param (
        # The path to the configuration file
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        # The new value for global_prep_cmd as an array of objects
        [Parameter(Mandatory)]
        [object[]]$Value
    )

    # Read the contents of the configuration file into an array of strings
    $config = Get-Content -Path $ConfigPath

    # Get the current value of global_prep_cmd as a JSON string
    $currentValueJson = Get-GlobalPrepCommand -ConfigPath $ConfigPath

    # Convert the new value to a JSON string
    $newValueJson = ConvertTo-Json -InputObject $Value -Compress

    # Replace the current value with the new value in the config array
    try {
        $config = $config -replace [regex]::Escape($currentValueJson), $newValueJson
    }
    catch {
        # If it failed, it probably does not exist yet.
        $config += "global_prep_cmd = $($newValueJson)"
    }



    # Write the modified config array back to the file
    $config | Set-Content -Path $ConfigPath -Force
}

function inverseMonitorSwapCommandsAndDeserialize() {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    $commands = $InputObject | ConvertFrom-Json 

    $ResolutionMatcherCommand = $commands | Where-Object { $_.do -like '*ResolutionMatcher*' } | Select-Object -First 1
    foreach ($command in $commands) {
        if ($command.do -like '*MonitorSwapAutomation*') {
            $old = $ResolutionMatcherCommand.undo
            $ResolutionMatcherCommand.undo = $command.undo
            $command.undo = $old
        }
    }

    return $commands
}



# Prior to removing, inverse the order if applicable.
$commands = Get-GlobalPrepCommand -ConfigPath $confPath | inverseMonitorSwapCommandsAndDeserialize
$commands = $commands | Remove-ResolutionMatcherCommand
Set-GlobalPrepCommand -ConfigPath $confPath -Value $commands

Write-Host "If you didn't see any errors, that means the script uninstalled without issues! You can close this window."

