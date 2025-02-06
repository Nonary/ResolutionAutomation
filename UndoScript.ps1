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

    ### 1. Read the Sunshine config file and extract the global_prep_cmd JSON array.
    try {
        $configContent = Get-Content -Path $settings.sunshineConfigPath -Raw
    }
    catch {
        Write-Error "Unable to read Sunshine config file at '$($settings.sunshineConfigPath)'. Error: $_"
        exit 1
    }

    if ($configContent -match 'global_prep_cmd\s*=\s*(\[[^\]]+\])') {
        $jsonText = $matches[1]
    }
    else {
        Write-Error "Could not find a valid 'global_prep_cmd' entry in the config file."
        exit 1
    }

    try {
        $prepCommands = $jsonText | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse global_prep_cmd JSON: $_"
        exit 1
    }
    if (-not ($prepCommands -is [System.Collections.IEnumerable])) {
        $prepCommands = @($prepCommands)
    }

    ### 2. Filter the commands so that only those whose undo command matches one of the desired script names are processed.
    $filteredCommands = @()
    foreach ($name in $desiredNames) {
        # Escape the script name for regex matching.
        $regexName = [regex]::Escape($name)
        $matchesForName = $prepCommands | Where-Object { $_.undo -match $regexName }
        if ($matchesForName) {
            $filteredCommands += $matchesForName
        }
    }

    if (-not $filteredCommands) {
        Write-Host "No matching undo commands found for the desired script names. Exiting."
        exit 0
    }

    ### 3. Order the commands in reverse of the installation order.
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

    ### 4. Execute the filtered undo commands synchronously.
    Write-Host "Starting undo for filtered installed scripts (in reverse order):"
    foreach ($cmd in $finalCommands) {

        if ($cmd.undo -and $cmd.undo.Trim() -ne "") {
            # Save the original undo command text.
            $undoCommand = $cmd.undo

            if ($undoCommand -contains "PlayniteWatcher" -or $undoCommand -contains "RTSSLimiter") {
                continue
            }
    
            # Look for the -file parameter and extract its value.
            if ($undoCommand -match '-file\s+"([^"]+)"') {
                $origFilePath = $matches[1]
                $origFileName = Split-Path $origFilePath -Leaf
    
                # If the file isn't already Helpers.ps1, replace it.
                if ($origFileName -ne "Helpers.ps1") {


                    $folder = Split-Path $origFilePath -Parent
                    $newFilePath = Join-Path $folder "Helpers.ps1"
    
                    # Replace the original file path with the new Helpers.ps1 path.
                    $undoCommand = $undoCommand -replace [regex]::Escape($origFilePath), $newFilePath

                    if ($undoCommand -notcontains "-t 1") {
                        $undoCommand = $undoCommand + " -t 1"
                    }
                    Write-Host "Modified undo command to: $undoCommand"
                }
            }
    
            Write-Host "Running undo command:"
            Write-Host "  $undoCommand"
            try {
                # Execute the modified undo command synchronously.
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
        Start-Sleep -Seconds 1  # Optional pause between commands.
    }
    

    Write-Host "All undo operations have been processed."

}
finally {
    # Always release and dispose of the mutex.
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
