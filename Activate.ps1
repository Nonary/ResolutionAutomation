# Define the path to the PowerShell script you want to launch
$scriptPath = "F:\sources\ResolutionAutomation\GS_SS-MatchResolution.ps1"

# Create a new PowerShell process to run the script with bypass execution policy and hidden window
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden

