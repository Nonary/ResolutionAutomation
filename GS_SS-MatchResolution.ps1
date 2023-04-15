

$lastStreamed = [System.DateTime]::MinValue
$hostResolution = Get-CimInstance -ClassName Win32_videocontroller  |  Where-Object {$_.CurrentRefreshRate -gt 0 -and $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } | Select-Object CurrentRefreshRate, CurrentHorizontalResolution, CurrentVerticalResolution -First 1
$onStreamEventTriggered = $false
while ($true) {
    if (UserIsStreaming) {
        $lastStreamed = Get-Date
        if (!$onStreamEventTriggered) {
            # Capture host resolution again, in case it changed recently.
            $hostResolution = Get-CimInstance -ClassName Win32_videocontroller  |  Where-Object {$_.CurrentRefreshRate -gt 0 -and $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } | Select-Object CurrentRefreshRate, CurrentHorizontalResolution, CurrentVerticalResolution -First 1
            Start-Sleep -Seconds $delaySettings.StartDelay
            $resolution = Apply-Overrides -resolution (Get-ClientResolution)
            Set-ScreenResolution -Width $resolution.width -Height $resolution.height -Freq $resolution.refresh
            $onStreamEventTriggered = $true
        }

    }
    elseif ($onStreamEventTriggered -and ((Get-Date) - $lastStreamed).TotalSeconds -gt $delaySettings.EndDelay) {
        Set-ScreenResolution -Width $hostResolution.CurrentHorizontalResolution -Height $hostResolution.CurrentVerticalResolution -Freq $hostResolution.CurrentRefreshRate
        $onStreamEventTriggered = $false
        break;
        
    }
    Start-Sleep -Seconds 1
}