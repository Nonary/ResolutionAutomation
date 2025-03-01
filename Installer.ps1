param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName,

    [Parameter(Position = 1, Mandatory = $true)]
    [Alias("i")]
    [string]$install
)
Set-Location (Split-Path $MyInvocation.MyCommand.Path -Parent)
$filePath = $($MyInvocation.MyCommand.Path)
$scriptRoot = Split-Path $filePath -Parent
$scriptPath = "$scriptRoot\StreamMonitor.ps1"
. .\Helpers.ps1 -n $scriptName
$settings = Get-Settings

# This script modifies the global_prep_cmd setting in the Sunshine/Apollo configuration files

function Test-UACEnabled {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $uacEnabled = Get-ItemProperty -Path $key -Name 'EnableLUA'
    return [bool]$uacEnabled.EnableLUA
}

$isAdmin = [bool]([System.Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')

# If the user is not an administrator and UAC is enabled, re-launch the script with elevated privileges
if (-not $isAdmin -and (Test-UACEnabled)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$filePath`" -n `"$scriptName`" -i `"$install`""
    exit
}

function Find-ConfigurationFiles {
    $sunshineDefaultPath = "C:\Program Files\Sunshine\config\sunshine.conf"
    $apolloDefaultPath = "C:\Program Files\Apollo\config\sunshine.conf"
    
    $sunshineFound = Test-Path $sunshineDefaultPath
    $apolloFound = Test-Path $apolloDefaultPath
    $configPaths = @{}
    
    # If either one is found, use their default paths
    if ($sunshineFound) {
        $configPaths["Sunshine"] = $sunshineDefaultPath
        Write-Host "Sunshine config found at: $sunshineDefaultPath"
    }
    
    if ($apolloFound) {
        $configPaths["Apollo"] = $apolloDefaultPath
        Write-Host "Apollo config found at: $apolloDefaultPath"
    }
    
    # Only prompt if neither is found
    if (-not $sunshineFound -and -not $apolloFound) {
        # Show error message dialog
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Neither Sunshine nor Apollo configuration could be found. Please locate a configuration file.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null

        # Open file dialog
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $fileDialog.Title = "Open sunshine.conf"
        $fileDialog.Filter = "Configuration files (*.conf)|*.conf"
        
        if ($fileDialog.ShowDialog() -eq "OK") {
            $selectedPath = $fileDialog.FileName
            # Check if the selected path is valid
            if (Test-Path $selectedPath) {
                Write-Host "File selected: $selectedPath"
                if ($selectedPath -like "*Apollo*") {
                    $configPaths["Apollo"] = $selectedPath
                } else {
                    $configPaths["Sunshine"] = $selectedPath
                }
            }
            else {
                Write-Error "Invalid file path selected."
                exit 1
            }
        }
        else {
            Write-Error "Configuration file dialog was canceled or no valid file was selected."
            exit 1
        }
    }
    
    return $configPaths
}

# Find configuration files
$configPaths = Find-ConfigurationFiles

# Save paths to settings
if ($configPaths.ContainsKey("Sunshine")) {
    Update-JsonProperty -FilePath "./settings.json" -Property "sunshineConfigPath" -NewValue $configPaths["Sunshine"]
}
if ($configPaths.ContainsKey("Apollo")) {
    Update-JsonProperty -FilePath "./settings.json" -Property "apolloConfigPath" -NewValue $configPaths["Apollo"]
}

# Get the current value of global_prep_cmd from the configuration file
function Get-GlobalPrepCommand {
    param (
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

# Remove any existing commands that contain the scripts name from the global_prep_cmd value
function Remove-Command {
    param (
        [string]$ConfigPath
    )

    # Get the current value of global_prep_cmd as a JSON string
    $globalPrepCmdJson = Get-GlobalPrepCommand -ConfigPath $ConfigPath

    # Convert the JSON string to an array of objects
    $globalPrepCmdArray = $globalPrepCmdJson | ConvertFrom-Json
    $filteredCommands = @()

    # Remove any existing matching Commands
    for ($i = 0; $i -lt $globalPrepCmdArray.Count; $i++) {
        if (-not ($globalPrepCmdArray[$i].do -like "*$scriptRoot*")) {
            $filteredCommands += $globalPrepCmdArray[$i]
        }
    }

    return [object[]]$filteredCommands
}

# Set a new value for global_prep_cmd in the configuration file
function Set-GlobalPrepCommand {
    param (
        [string]$ConfigPath,
        # The new value for global_prep_cmd as an array of objects
        [object[]]$Value
    )

    if ($null -eq $Value) {
        $Value = [object[]]@()
    }

    # Read the contents of the configuration file into an array of strings
    $config = Get-Content -Path $ConfigPath

    # Get the current value of global_prep_cmd as a JSON string
    $currentValueJson = Get-GlobalPrepCommand -ConfigPath $ConfigPath

    # Convert the new value to a JSON string - ensure proper JSON types
    $newValueJson = ConvertTo-Json -InputObject $Value -Compress -Depth 10
    # Fix boolean values to be JSON compliant
    $newValueJson = $newValueJson -replace '"elevated"\s*:\s*"true"', '"elevated": true'
    $newValueJson = $newValueJson -replace '"elevated"\s*:\s*"false"', '"elevated": false'

    # Replace the current value with the new value in the config array
    try {
        $config = $config -replace [regex]::Escape($currentValueJson), $newValueJson
    }
    catch {
        # If it failed, it probably does not exist yet.
        # In the event the config only has one line, we will cast this to an object array so it appends a new line automatically.

        if ($Value.Length -eq 0) {
            [object[]]$config += "global_prep_cmd = []"
        }
        else {
            [object[]]$config += "global_prep_cmd = $($newValueJson)"
        }
    }
    # Write the modified config array back to the file
    $config | Set-Content -Path $ConfigPath -Force
}

function OrderCommands($commands, $scriptNames) {
    $orderedCommands = New-Object System.Collections.ArrayList

    if($commands -isnot [System.Collections.IEnumerable]) {
        # PowerShell likes to magically change types on you, so we have to check for this
        $commands = @(, $commands)
    }

    $orderedCommands.AddRange($commands)

    for ($i = 1; $i -lt $scriptNames.Count; $i++) {
        if ($i - 1 -lt 0) {
            continue
        }

        $before = $scriptNames[$i - 1]
        $after = $scriptNames[$i]

        $afterCommand = $orderedCommands | Where-Object { $_.do -like "*$after*" -or $_.undo -like "*$after*" } | Select-Object -First 1

        $beforeIndex = $null
        for ($j = 0; $j -lt $orderedCommands.Count; $j++) {
            if ($orderedCommands[$j].do -like "*$before*" -or $orderedCommands[$j].undo -like "*$before*") {
                $beforeIndex = $j
                break
            }
        }
        $afterIndex = $null
        for ($j = 0; $j -lt $orderedCommands.Count; $j++) {
            if ($orderedCommands[$j].do -like "*$after*" -or $orderedCommands[$j].undo -like "*$after*") {
                $afterIndex = $j
                break
            }
        }

        if ($null -ne $afterIndex -and ($afterIndex -lt $beforeIndex)) {
            $orderedCommands.RemoveAt($afterIndex)
            $orderedCommands.Insert($beforeIndex, $afterCommand)
        }
    }

    $orderedCommands
}

function Add-Command {
    param (
        [string]$ConfigPath
    )

    # Remove any existing commands that contain the scripts name from the global_prep_cmd value
    $globalPrepCmdArray = Remove-Command -ConfigPath $ConfigPath

    $command = [PSCustomObject]@{
        do       = "powershell.exe -executionpolicy bypass -file `"$($scriptPath)`" -n $scriptName"
        elevated = $false
        undo     = "powershell.exe -executionpolicy bypass -file `"$($scriptRoot)\UndoScript.ps1`" -n $scriptName"
    }

    # Add the new object to the global_prep_cmd array
    [object[]]$globalPrepCmdArray += $command

    return [object[]]$globalPrepCmdArray
}

# Process each found configuration file
foreach ($key in $configPaths.Keys) {
    $configPath = $configPaths[$key]
    
    $commands = @()
    if ($install -eq 1) {
        $commands = Add-Command -ConfigPath $configPath
    }
    else {
        $commands = Remove-Command -ConfigPath $configPath 
    }

    if ($settings.installationOrderPreferences.enabled) {
        $commands = OrderCommands $commands $settings.installationOrderPreferences.scriptNames
    }

    Set-GlobalPrepCommand -ConfigPath $configPath -Value $commands
    
    if ($key -eq "Sunshine") {
        $service = Get-Service -ErrorAction Ignore | Where-Object { $_.Name -eq 'sunshinesvc' -or $_.Name -eq 'SunshineService' }
        $service | Restart-Service -WarningAction SilentlyContinue
        Write-Host "Sunshine configuration updated successfully!"
    } elseif ($key -eq "Apollo") {
        $service = Get-Service -ErrorAction Ignore | Where-Object { $_.Name -eq 'Apollo Service' }
        # Uncomment the line below if you want to automatically restart the service
        $service | Restart-Service -WarningAction SilentlyContinue
        Write-Host "Apollo configuration updated successfully!"
    }
}

Write-Host "If you didn't see any errors, that means the script installed without issues! You can close this window."
