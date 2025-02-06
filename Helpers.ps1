param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName,
    [Alias("t")]
    [Parameter(Position = 1, Mandatory = $false)]
    [int]$terminate
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
$script:attempt = 0
function OnStreamEndAsJob() {
    return Start-Job -Name "$scriptName-OnStreamEnd" -ScriptBlock {
        param($path, $scriptName, $arguments)

        function Write-Debug($message){
            if ($arguments['debug']) {
                Write-Host "DEBUG: $message"
            }
        }

        Write-Host $arguments
        
        Write-Debug "Setting location to $path"
        Set-Location $path
        Write-Debug "Loading Helpers.ps1 with script name $scriptName"
        . .\Helpers.ps1 -n $scriptName
        Write-Debug "Loading Events.ps1 with script name $scriptName"
        . .\Events.ps1 -n $scriptName
        
        Write-Host "Stream has ended, now invoking code"
        Write-Debug "Creating pipe with name $scriptName-OnStreamEnd"
        $job = Create-Pipe -pipeName "$scriptName-OnStreamEnd" 

        while ($true) {
            $maxTries = 25
            $tries = 0

            Write-Debug "Checking job state: $($job.State)"
            if ($job.State -eq "Completed") {
                Write-Host "Another instance of $scriptName has been started again. This current session is now redundant and will terminate without further action."
                Write-Debug "Job state is 'Completed'. Exiting loop."
                break;
            }

            Write-Debug "Invoking OnStreamEnd with arguments: $arguments"
            if ((OnStreamEnd $arguments)) {
                Write-Debug "OnStreamEnd returned true. Exiting loop."
                break;
            }

        
            if ((IsCurrentlyStreaming)) {
                Write-Host "Streaming is active. To prevent potential conflicts, this script will now terminate prematurely."
            }
        

            while (($tries -lt $maxTries) -and ($job.State -ne "Completed")) {
                Start-Sleep -Milliseconds 200
                $tries++
            }
        }

        Write-Debug "Sending 'Terminate' message to pipe $scriptName-OnStreamEnd"
        Send-PipeMessage "$scriptName-OnStreamEnd" Terminate
    } -ArgumentList $path, $scriptName, $script:arguments
}


function IsCurrentlyStreaming() {
    $sunshineProcess = Get-Process sunshine -ErrorAction SilentlyContinue

    if ($null -eq $sunshineProcess) {
        return $false
    }
    return $null -ne (Get-NetUDPEndpoint -OwningProcess $sunshineProcess.Id -ErrorAction Ignore)
}

function Stop-Script() {
    Send-PipeMessage -pipeName $scriptName Terminate
}
function Send-PipeMessage($pipeName, $message) {
    Write-Debug "Attempting to send message to pipe: $pipeName"

    $pipeExists = Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -eq $pipeName }
    Write-Debug "Pipe exists check: $($pipeExists.Length -gt 0)"
    
    if ($pipeExists.Length -gt 0) {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::Out)
        Write-Debug "Connecting to pipe: $pipeName"
        
        $pipe.Connect(3000)
        $streamWriter = New-Object System.IO.StreamWriter($pipe)
        Write-Debug "Sending message: $message"
        
        $streamWriter.WriteLine($message)
        try {
            $streamWriter.Flush()
            $streamWriter.Dispose()
            $pipe.Dispose()
            Write-Debug "Message sent and resources disposed successfully."
        }
        catch {
            Write-Debug "Error during disposal: $_"
            # We don't care if the disposal fails, this is common with async pipes.
            # Also, this powershell script will terminate anyway.
        }
    }
    else {
        Write-Debug "Pipe not found: $pipeName"
    }
}


function Create-Pipe($pipeName) {
    return Start-Job -Name "$pipeName-PipeJob" -ScriptBlock {
        param($pipeName, $scriptName) 
        Register-EngineEvent -SourceIdentifier $scriptName -Forward
        
        $pipe = New-Object System.IO.Pipes.NamedPipeServerStream($pipeName, [System.IO.Pipes.PipeDirection]::In, 10, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)

        $streamReader = New-Object System.IO.StreamReader($pipe)
        Write-Host "Waiting for named pipe to recieve kill command"
        $pipe.WaitForConnection()

        $message = $streamReader.ReadLine()
        if ($message) {
            Write-Host "Terminating pipe..."
            $pipe.Dispose()
            $streamReader.Dispose()
            New-Event -SourceIdentifier $scriptName -MessageData $message
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
    $timeStamp = [int][double]::Parse((Get-Date -UFormat "%s"))
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
    }
    catch {
        Write-Error "Failed to parse JSON: $_"
    }
}

function Update-JsonProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Property,
        
        [Parameter(Mandatory = $true)]
        [object]$NewValue
    )

    # Read the file as a single string.
    $content = Get-Content -Path $FilePath -Raw

    if ($NewValue -is [string]) {
        # Convert the string to a JSON-compliant string.
        # ConvertTo-Json will take care of escaping characters properly.
        $formattedValue = (ConvertTo-Json $NewValue -Compress)
    }
    else {
        $formattedValue = $NewValue.ToString()
    }

    # Build a regex pattern for matching the property.
    $escapedProperty = [regex]::Escape($Property)
    $pattern = '"' + $escapedProperty + '"\s*:\s*[^,}\r\n]+'

    # Build the replacement string.
    $replacement = '"' + $Property + '": ' + $formattedValue

    # Replace the matching part in the content.
    $updatedContent = [regex]::Replace($content, $pattern, { param($match) $replacement })

    # Write the updated content back.
    Set-Content -Path $FilePath -Value $updatedContent
}



function Wait-ForStreamEndJobToComplete() {
    $job = OnStreamEndAsJob
    while ($job.State -ne "Completed") {
        $job | Receive-Job
        Start-Sleep -Seconds 1
    }
    $job | Wait-Job | Receive-Job
}


if ($terminate -eq 1) {
    Write-Host "Stopping Script"
    Stop-Script | Out-Null
}
