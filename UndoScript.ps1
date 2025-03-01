# UndoFilteredFromSunshineConfig.ps1
param(
    # Used by Helpers.ps1 (and for filtering undo commands)
    [Parameter(Mandatory = $true)]
    [Alias("n")]
    [string]$ScriptName,

    # When this switch is not present, the script will relaunch itself detached via WMI.
    [Switch]$Detached
)

# If not already running detached, re-launch self via WMI and exit.
if (-not $Detached) {
    # Get the full path of this script.
    $scriptPath = $MyInvocation.MyCommand.Definition
    # Build the command line; note that we add the -Detached switch.
    $command = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`" -ScriptName `"$ScriptName`" -Detached"
    Write-Host "Launching detached instance via WMI: $command"
    # Launch using WMI Create process.
    ([wmiclass]"\\.\root\cimv2:Win32_Process").Create($command) | Out-Null
    exit
}

# Now we are running in detached mode.
# Set the working directory to this script's folder.
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path

# Load helper functions (assumes Helpers.ps1 exists in the same folder)
. .\Helpers.ps1 -n $ScriptName

# Load settings (this function should be defined in Helpers.ps1)
$settings = Get-Settings

# Define a unique, system-wide mutex name.
$mutexName = "Global\SunshineUndoMutex"
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref] $createdNew)

if (-not $createdNew) {
    Write-Host "Undo process already in progress or executed. Exiting..."
    exit
}

try {
    Write-Host "Acquired mutex. Running undo process..."

    # Retrieve the list of script names from settings.
    $desiredNames = $settings.installationOrderPreferences.scriptNames
    if (-not $desiredNames) {
        Write-Error "No script names defined in settings.installationOrderPreferences.scriptNames."
        exit 1
    }

    # Create a hashtable to store unique commands by their undo command
    $commandHashMap = @{}

    # Function to read global_prep_cmd from a config file
    function Get-GlobalPrepCommands {
        param (
            [string]$ConfigPath
        )
        
        if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
            Write-Host "Config path not found or not specified: $ConfigPath"
            return @()
        }
        
        try {
            $configContent = Get-Content -Path $ConfigPath -Raw
            
            if ($configContent -match 'global_prep_cmd\s*=\s*(\[[^\]]+\])') {
                $jsonText = $matches[1]
                try {
                    $commands = $jsonText | ConvertFrom-Json
                    if (-not ($commands -is [System.Collections.IEnumerable])) {
                        $commands = @($commands)
                    }
                    return $commands
                }
                catch {
                    Write-Error "Failed to parse global_prep_cmd JSON from $ConfigPath`: $_"
                    return @()
                }
            }
            else {
                Write-Host "No valid 'global_prep_cmd' entry found in $ConfigPath."
                return @()
            }
        }
        catch {
            Write-Error "Unable to read config file at '$ConfigPath'. Error: $_"
            return @()
        }
    }
    
    # Get commands from Sunshine config if available
    if ($settings.sunshineConfigPath) {
        Write-Host "Reading commands from Sunshine config: $($settings.sunshineConfigPath)"
        $sunshineCommands = Get-GlobalPrepCommands -ConfigPath $settings.sunshineConfigPath
        foreach ($cmd in $sunshineCommands) {
            if ($cmd.undo) {
                # Use the undo command as the key to avoid duplicates
                $commandHashMap[$cmd.undo] = $cmd
            }
        }
    }
    
    # Get commands from Apollo config if available
    if ($settings.apolloConfPath) {
        Write-Host "Reading commands from Apollo config: $($settings.apolloConfPath)"
        $apolloCommands = Get-GlobalPrepCommands -ConfigPath $settings.apolloConfPath
        foreach ($cmd in $apolloCommands) {
            if ($cmd.undo) {
                # This will overwrite any duplicate keys from Sunshine config
                $commandHashMap[$cmd.undo] = $cmd
            }
        }
    }
    
    # Convert the hashtable values back to an array
    $allPrepCommands = @($commandHashMap.Values)
    
    Write-Host "Total unique commands found: $($allPrepCommands.Count)"

    # Filter the commands to only include those matching our desired script names
    $filteredCommands = @()
    foreach ($name in $desiredNames) {
        $regexName = [regex]::Escape($name)
        $matchesForName = $allPrepCommands | Where-Object { $_.undo -match $regexName }
        if ($matchesForName) {
            $filteredCommands += $matchesForName
        }
    }

    if (-not $filteredCommands) {
        Write-Host "No matching undo commands found for the desired script names. Exiting."
        exit 0
    }

    # Order the commands in reverse of the installation order
    $desiredNamesReversed = $desiredNames.Clone()
    [Array]::Reverse($desiredNamesReversed)
    $finalCommands = @()
    foreach ($name in $desiredNamesReversed) {
        $cmdForName = $filteredCommands | Where-Object { $_.undo -match [regex]::Escape($name) }
        if ($cmdForName) {
            # Add all matching commands (if more than one per script)
            $finalCommands += $cmdForName
        }
    }

    # Execute the filtered undo commands synchronously
    Write-Host "Starting undo for filtered installed scripts (in reverse order):"
    foreach ($cmd in $finalCommands) {
        if ($cmd.undo -and $cmd.undo.Trim() -ne "") {
            # Save the original undo command text
            $undoCommand = $cmd.undo

            if ($undoCommand -match "PlayniteWatcher" -or $undoCommand -match "RTSSLimiter") {
                Write-Host "Skipping undo command related to PlayniteWatcher or RTSSLimiter."
                continue
            }
    
            # Look for the -file parameter and extract its value
            if ($undoCommand -match '-file\s+"([^"]+)"') {
                $origFilePath = $matches[1]
                $origFileName = Split-Path $origFilePath -Leaf
    
                # If the file isn't already Helpers.ps1, replace it
                if ($origFileName -ne "Helpers.ps1") {
                    $folder = Split-Path $origFilePath -Parent
                    $newFilePath = Join-Path $folder "Helpers.ps1"
    
                    # Replace the original file path with the new Helpers.ps1 path
                    $undoCommand = $undoCommand -replace [regex]::Escape($origFilePath), $newFilePath

                    if ($undoCommand -notmatch "-t\s+1") {
                        $undoCommand = $undoCommand + " -t 1"
                    }
                    Write-Host "Modified undo command to: $undoCommand"
                }
            }
    
            Write-Host "Running undo command:"
            Write-Host "  $undoCommand"
            try {
                # Execute the modified undo command synchronously
                Invoke-Expression $undoCommand
                Write-Host "Undo command completed."
            }
            catch {
                Write-Warning "Failed to run undo command for one of the scripts: $_"
            }
        }
        else {
            Write-Host "No undo command for this entry. Skipping."
        }
        Start-Sleep -Seconds 1  # Optional pause between commands
    }
    
    Write-Host "All undo operations have been processed."
}
finally {
    # Always release and dispose of the mutex
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
