param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias("n")]
    [string]$scriptName,

    [Parameter(Position = 1)]
    [Alias("sib")]
    [bool]$startInBackground
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
. .\Helpers.ps1 -n $scriptName
. .\Events.ps1 -n $scriptName
$settings = Get-Settings
$DebugPreference = if ($settings.debug) { "Continue" } else { "SilentlyContinue" }
# Since pre-commands in sunshine are synchronous, we'll launch this script again in another powershell process
if ($startInBackground -eq $false) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $arguments = "-ExecutionPolicy Bypass -Command `"& '$scriptPath\StreamMonitor.ps1' -scriptName $scriptName -sib 1`""
    Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden
    Start-Sleep -Seconds $settings.startDelay
    exit
}


Remove-OldLogs
Start-Logging

# OPTIONAL MUTEX HANDLING
# Create a mutex to prevent multiple instances of this script from running simultaneously.
$lock = $false
$mutex = New-Object System.Threading.Mutex($false, $scriptName, [ref]$lock)

# Exit the script if another instance is already running.
if (-not $mutex.WaitOne(0)) {
    Write-Host "Exiting: Another instance of the script is currently running."
    exit
}

if (-not $mutex) {
    ### If you don't use a mutex, you can optionally fan the hammer
    for ($i = 0; $i -lt 6; $i++) {
        Send-PipeMessage $scriptName NewSession
        Send-PipeMessage "$scriptName-OnStreamEnd" Terminate
    }
}


# END OF OPTIONAL MUTEX HANDLING


try {
    
    # Asynchronously start the script, so we can use a named pipe to terminate it.
    Start-Job -Name "$($scriptName)Job" -ScriptBlock {
        param($path, $scriptName, $gracePeriod)
        . $path\Helpers.ps1 -n $scriptName
        $lastStreamed = Get-Date


        Register-EngineEvent -SourceIdentifier $scriptName -Forward
        New-Event -SourceIdentifier $scriptName -MessageData "Start"
        while ($true) {
            try {
                if ((IsCurrentlyStreaming)) {
                    $lastStreamed = Get-Date
                }
                else {
                    if (((Get-Date) - $lastStreamed).TotalSeconds -gt $gracePeriod) {
                        New-Event -SourceIdentifier $scriptName -MessageData "GracePeriodExpired"
                        break;
                    }
        
                }
            }
            finally {
                Start-Sleep -Seconds 1
            }
        }
    
    } -ArgumentList $path, $scriptName, $settings.gracePeriod | Out-Null


    # This might look like black magic, but basically we don't have to monitor this pipe because it fires off an event.
    Create-Pipe $scriptName | Out-Null

    Write-Host "Waiting for the next event to be called... (for starting/ending stream)"
    while ($true) {
        Start-Sleep -Seconds 1
        $eventFired = Get-Event -SourceIdentifier $scriptName -ErrorAction SilentlyContinue
        if ($null -ne $eventFired) {
            $eventName = $eventFired.MessageData
            Write-Host "Processing event: $eventName"
            if ($eventName -eq "Start") {
                OnStreamStart
            }
            elseif ($eventName -eq "NewSession") {
                Write-Host "A new session of this script has been started. To avoid conflicts, this session will now terminate. This is a normal process and not an error."
                break;
            }
            elseif ($eventName -eq "GracePeriodExpired") {
                Write-Host "Stream has been suspended beyond the defined grace period. We will now treat this as if you ended the stream. If this was unintentional or if you wish to extend the grace period, please adjust the grace period timeout in the settings.json file."
                Wait-ForStreamEndJobToComplete
                break;
            }
            else {
                Wait-ForStreamEndJobToComplete
                break;
            }
            Remove-Event -EventIdentifier $eventFired.EventIdentifier
        }
    }
}
finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
    }
    Stop-Logging
}
