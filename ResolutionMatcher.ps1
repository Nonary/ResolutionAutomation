param($async)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
$settings = Get-Content -Path .\settings.json | ConvertFrom-Json

# Since pre-commands in sunshine are synchronous, we'll launch this script again in another powershell process
if ($null -eq $async) {
    Start-Process powershell.exe  -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" $($MyInvocation.MyCommand.UnboundArguments) -async $true" -WindowStyle Hidden
    exit
}

Start-Transcript -Path .\log.txt
. .\ResolutionMatcher-Functions.ps1
$hostResolutions = Get-HostResolution
$lock = $false



$mutexName = "ResolutionMatcher"
$resolutionMutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$lock)

# There is no need to have more than one of these scripts running.
if (-not $resolutionMutex.WaitOne(0)) {
    Write-Host "Another instance of the script is already running. Exiting..."
    exit
}

try {
    
    # Asynchronously start the ResolutionMatcher, so we can use a named pipe to terminate it.
    Start-Job -Name ResolutionMatcherJob -ScriptBlock {
        param($path, $revertDelay)
        . $path\ResolutionMatcher-Functions.ps1
        $lastStreamed = Get-Date


        Register-EngineEvent -SourceIdentifier ResolutionMatcher -Forward
        New-Event -SourceIdentifier ResolutionMatcher -MessageData "Start"
        while ($true) {
            try {
                if ((IsCurrentlyStreaming)) {
                    $lastStreamed = Get-Date
                }
                else {
                    if (((Get-Date) - $lastStreamed).TotalSeconds -gt $revertDelay) {
                        New-Event -SourceIdentifier ResolutionMatcher -MessageData "End"
                        break;
                    }
        
                }
            }
            finally {
                Start-Sleep -Seconds 1
            }
        }
    
    } -ArgumentList $path, $settings.revertDelay


    # To allow other powershell scripts to communicate to this one.
    Start-Job -Name "ResolutionMatcher-Pipe" -ScriptBlock {
        $pipeName = "ResolutionMatcher"
        Remove-Item "\\.\pipe\$pipeName" -ErrorAction Ignore
        $pipe = New-Object System.IO.Pipes.NamedPipeServerStream($pipeName, [System.IO.Pipes.PipeDirection]::In, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)

        $streamReader = New-Object System.IO.StreamReader($pipe)
        Write-Output "Waiting for named pipe to recieve kill command"
        $pipe.WaitForConnection()

        $message = $streamReader.ReadLine()
        if ($message -eq "Terminate") {
            Write-Output "Terminating pipe..."
            $pipe.Dispose()
            $streamReader.Dispose()
        }
    }



    $eventMessageCount = 0
    Write-Host "Waiting for the next event to be called... (for starting/ending stream)"
    while ($true) {
        $eventMessageCount += 1
        Start-Sleep -Seconds 1
        $eventFired = Get-Event -SourceIdentifier ResolutionMatcher -ErrorAction SilentlyContinue
        $pipeJob = Get-Job -Name "ResolutionMatcher-Pipe"
        if ($null -ne $eventFired) {
            $eventName = $eventFired.MessageData
            Write-Host "Processing event: $eventName"
            if ($eventName -eq "Start") {
                OnStreamStart -width $env:SUNSHINE_CLIENT_WIDTH -height $env:SUNSHINE_CLIENT_HEIGHT -refresh $env:SUNSHINE_CLIENT_FPS 
            }
            elseif ($eventName -eq "End") {
                OnStreamEnd $hostResolutions
                break;
            }
            Remove-Event -EventIdentifier $eventFired.EventIdentifier
        }
        elseif ($pipeJob.State -eq "Completed") {
            Write-Host "Request to terminate has been processed, script will now revert resolution."
            OnStreamEnd $hostResolutions
            break;
        }
        elseif($eventMessageCount -gt 59) {
            Write-Host "Still waiting for the next event to fire..."
            $eventMessageCount = 0
        }

    
    }
}
finally {
    Remove-Item "\\.\pipe\ResolutionMatcher" -ErrorAction Ignore
    $resolutionMutex.ReleaseMutex()
    Remove-Event -SourceIdentifier ResolutionMatcher -ErrorAction Ignore
    Stop-Transcript
}
