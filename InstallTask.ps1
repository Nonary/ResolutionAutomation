param($install, $start)

if($install -eq $true -or $install -eq "true"){
Write-Host "Installing Task"
$file_location = Get-Item ".\ResolutionMatcher.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-windowstyle hidden -executionpolicy bypass -file `"$($file_location.FullName)`"" -WorkingDirectory $file_location.Directory
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable  -DontStopOnIdleEnd -ExecutionTimeLimit 0 -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 5
$trigger = New-ScheduledTaskTrigger -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -Once

#Reinstall Task

$taskExists = Get-ScheduledTask -TaskName "Match GameStream Resolution" -ErrorAction Ignore
if($taskExists){
    Write-Host "Existing task was found, deleting this task so it can be recreated again"
    # If user moves folder where script is at, they will have to install again, so let's remove existing task if exists.
    $taskExists | Unregister-ScheduledTask -Confirm:$false
}


$task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings

Register-ScheduledTask -InputObject $task -TaskName "Match GameStream Resolution" | Out-Null

Write-Host "Task was installed sucessfully."
Start-ScheduledTask -TaskName "Match GameStream Resolution" | Out-Null

# We can't make a scheduled task start at logon without admin, so this is a workaround to that.
New-Item -Name "ResolutionMatcher.bat" -Value "powershell.exe -windowstyle hidden -executionpolicy bypass -command `"Start-ScheduledTask -TaskName 'Match GameStream Resolution' | Out-Null`"" -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Force | Out-Null

}


elseif($install -eq $false -or $install -eq "false") {
    Write-Host "Uninstalling Task"
    Get-ScheduledTask -TaskName "Match GameStream Resolution" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "Match GameStream Resolution" | Unregister-ScheduledTask -Confirm:$false
    Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ResolutionMatcher.bat" -Force -Confirm:$false | Out-Null
    Write-Host "Task was removed successfully."
}


