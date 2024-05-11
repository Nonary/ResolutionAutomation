param(
    [Parameter(Position=0, Mandatory=$true)]
    [Alias("n")]
    [string]$scriptName,
    [Alias("t")]
    [Parameter(Position=1, Mandatory=$false)]
    [bool]$terminate
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
$script:attempt = 0

function OnStreamEndAsJob() {

    return Start-Job -Name "$scriptName-OnStreamEnd" -ScriptBlock {
        param($path, $scriptName, $arguments)
        Set-Location $path
        . .\Helpers.ps1 -n $scriptName
        . .\Events.ps1 -n $scriptName
    
        Write-Host "Stream has ended, now invoking code"
        $job = Create-Pipe -pipeName "$scriptName-OnStreamEnd" 

        while ($true) {
            $maxTries = 25
            $tries = 0
        
            if ($job.State -eq "Completed") {
                Write-Host "Another instance of $scriptName has been started again. This current session is now redundant and will terminate without further action."
                break;
            }
        
            if ((IsCurrentlyStreaming)) {
                Write-Host "Streaming is active. To prevent potential conflicts, this script will now terminate prematurely."
            }
        
            if ((OnStreamEnd $arguments)) {
                break;
            }
        
            while (($tries -lt $maxTries) -and ($job.State -ne "Completed")) {
                Start-Sleep -Milliseconds 200
                $tries++
            }
        
        }
        # Allow job to complete by terminating the pipe, this line wouldn't be reached unless the OnStreamEnd was successful.
        Send-PipeMessage "$scriptName-OnStreamEnd" Terminate
    } -ArgumentList $path, $scriptName, $script:arguments
}


function IsSunshineUser() {
    return $null -ne (Get-Process sunshine -ErrorAction SilentlyContinue)
}

function IsCurrentlyStreaming() {
    if (IsSunshineUser) {
        return $null -ne (Get-NetUDPEndpoint -OwningProcess (Get-Process sunshine).Id -ErrorAction Ignore)
    }

    return $null -ne (Get-Process nvstreamer -ErrorAction SilentlyContinue)
}

function Stop-Script() {
    Send-PipeMessage -pipeName $scriptName Terminate
}


function Send-PipeMessage($pipeName, $message) {
    $pipeExists = Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -eq $pipeName } 
    if ($pipeExists.Length -gt 0) {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::Out)
        $pipe.Connect(3)
        $streamWriter = New-Object System.IO.StreamWriter($pipe)
        $streamWriter.WriteLine($message)
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

function Create-Pipe($pipeName) {
    return Start-Job -Name "$pipeName-PipeJob" -ScriptBlock {
        param($pipeName, $scriptName) 
        Register-EngineEvent -SourceIdentifier $scriptName -Forward
        
        for ($i = 0; $i -lt 10; $i++) {
            # We could be pending a previous termination, so lets wait up to 10 seconds.
            if (-not (Test-Path "\\.\pipe\$pipeName")) {
                break
            }
            
            Start-Sleep -Seconds 1
        }
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
            New-Event -SourceIdentifier $scriptName -MessageData "$pipeName-Terminated"
        }
    } -ArgumentList $pipeName, $scriptName
}

function Remove-OldLogs {

    # Get all log files in the directory
    $logFiles = Get-ChildItem -Path './logs' -Filter "log_*.txt" -ErrorAction SilentlyContinue

    # Sort the files by creation time, oldest first
    $sortedFiles = $logFiles | Sort-Object -Property CreationTime -ErrorAction SilentlyContinue

    if ($sortedFiles) {
        # Calculate how many files to delete
        $filesToDelete = $sortedFiles.Count - 10

        # Check if there are more than 10 files
        if ($filesToDelete -gt 0) {
            # Delete the oldest files, keeping the latest 10
            $sortedFiles[0..($filesToDelete - 1)] | Remove-Item -Force
        } 
    }
}

function Start-Logging {
    # Get the current timestamp
    $timeStamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
    $logDirectory = "./logs"

    # Define the path and filename for the log file
    $logFileName = "log_$timeStamp.txt"
    $logFilePath = Join-Path $logDirectory $logFileName

    # Check if the log directory exists, and create it if it does not
    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory
    }

    # Start logging to the log file
    Start-Transcript -Path $logFilePath
}

function Stop-Logging {
    Stop-Transcript
}


function Get-Settings {
    # Read the file content
    $jsonContent = Get-Content -Path ".\settings.json" -Raw

    # Remove single line comments
    $jsonContent = $jsonContent -replace '//.*', ''

    # Remove multi-line comments
    $jsonContent = $jsonContent -replace '/\*[\s\S]*?\*/', ''

    # Remove trailing commas from arrays and objects
    $jsonContent = $jsonContent -replace ',\s*([\]}])', '$1'

    try {
        # Convert JSON content to PowerShell object
        $jsonObject = $jsonContent | ConvertFrom-Json
        return $jsonObject
    } catch {
        Write-Error "Failed to parse JSON: $_"
    }
}



if ($terminate) {
    Write-Host "Stopping Script"
    Stop-Script | Out-Null
}
