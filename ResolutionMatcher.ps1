param($async)
$path = "Insert Path Here, or Run the Install_as_Precommand.ps1 file"

# Since pre-commands in sunshine are synchronous, we'll launch this script again in another powershell process
if ($null -eq $async) {
    Start-Process powershell.exe  -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`" $($MyInvocation.MyCommand.UnboundArguments) -async $true" -WindowStyle Hidden
    Start-Sleep -Seconds 1
}

Set-Location $path
. $path\ResolutionMatcher-Functions.ps1
$lock = $false


$mutexName = "ResolutionMatcher"
$resolutionMutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$lock)

# There is no need to have more than one of these scripts running.
if (-not $resolutionMutex.WaitOne(0)) {
    Write-Host "Another instance of the script is already running. Exiting..."
    exit
}


# Asynchronously start the Resolution Matcher, so we can use a named pipe to terminate it.
Start-Job -Name ResolutionMatcherJob -ScriptBlock {
    param($path)
    . $path\MonitorSwap-Functions.ps1
    $lastStreamed = Get-Date


    Register-EngineEvent -SourceIdentifier ResolutionMatcher -Forward
    New-Event -SourceIdentifier ResolutionMatcher -MessageData { OnStreamStart }
    while ($true) {
        if ((IsCurrentlyStreaming)) {
            $lastStreamed = Get-Date
        }
        else {
            if (((Get-Date) - $lastStreamed).TotalSeconds -gt 120) {
                Write-Output "Ending the stream script"
                New-Event -SourceIdentifier ResolutionMatcher -MessageData { OnStreamEnd; break }
                break;
            }
    
        }
        Start-Sleep -Seconds 1
    }
    
} -ArgumentList $path


# To allow other powershell scripts to communicate to this one.
Start-Job -Name NamedPipeJob -ScriptBlock {
    $pipeName = "ResolutionMatcher"
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






while ($true) {
    Start-Sleep -Seconds 1
    $eventFired = Get-Event -SourceIdentifier ResolutionMatcher -ErrorAction SilentlyContinue
    $pipeJob = Get-Job -Name "NamedPipeJob"
    if ($null -ne $eventFired) {
        Write-Host "Processing event..."
        $eventData = [scriptblock]::Create($eventFired.MessageData)
        $eventData.Invoke()
        Remove-Event -SourceIdentifier ResolutionMatcher
    }
    elseif ($pipeJob.State -eq "Completed") {
        Write-Host "Request to terminate has been processed, script will now revert resolution."
        OnStreamEnd
        break;
    }
    else {
        Write-Host "Waiting for next event..."
    }

    
}

$resolutionMutex.ReleaseMutex()
