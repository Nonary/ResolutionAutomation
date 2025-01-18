@echo off
where pwsh >nul 2>&1 || where powershell.exe >nul 2>&1 || (
    echo No PowerShell installation found at all
    pause
    exit /b 1
)
where pwsh >nul 2>&1 && (
    pwsh -executionpolicy bypass -file ./Installer.ps1 -n ResolutionMatcher -i 0
) || (
    powershell.exe -executionpolicy bypass -file ./Installer.ps1 -n ResolutionMatcher -i 0
)
pause
