param(
    [string]$scriptName
)

$whiteListedEntries = @("Packager.ps1", "Releases", "*.txt", ".gitignore", "logs", ".vscode", "ChatGPT")
$releaseBasePath = "Releases"
$releasePath = Join-Path -Path $releaseBasePath -ChildPath $scriptName
$assetsPath = Join-Path -Path $releaseBasePath -ChildPath "assets"

# Remove existing release directory if it exists
Remove-Item -Force $releasePath -Recurse -ErrorAction SilentlyContinue

# Ensure the Releases directory exists
if (-not (Test-Path -Path $releaseBasePath)) {
    New-Item -ItemType Directory -Path $releaseBasePath | Out-Null
}

# Ensure the assets directory exists
if (-not (Test-Path -Path $assetsPath)) {
    New-Item -ItemType Directory -Path $assetsPath | Out-Null
}

# Get all top-level items from the current directory, excluding the Releases directory
$items = Get-ChildItem -Path . | Where-Object {
    $_.FullName -notmatch "^\.\\Releases(\\|$)"
}

# Create a hashtable for quick whitelist lookup
$whitelistHash = @{}
foreach ($whitelist in $whiteListedEntries) {
    $whitelistHash[$whitelist] = $true
}

# Create a hashtable to store asset files and directories for quick lookup
$assetItems = @{}
Get-ChildItem -Path $assetsPath -Recurse | ForEach-Object {
    $assetItems[$_.Name] = $_.FullName
}

# Filter and replace items efficiently
$filteredItems = @()
foreach ($item in $items) {
    $itemName = $item.Name

    # Check for whitelist
    $isWhitelisted = $false
    foreach ($key in $whitelistHash.Keys) {
        if ($itemName -like $key) {
            $isWhitelisted = $true
            break
        }
    }

    if (-not $isWhitelisted) {
        if ($assetItems.ContainsKey($itemName)) {
            $filteredItems += Get-Item -Path $assetItems[$itemName]
        } else {
            $filteredItems += $item
        }
    }
}

# Create the release directory named after the script
if (-not (Test-Path -Path $releasePath)) {
    New-Item -ItemType Directory -Path $releasePath | Out-Null
}

# Copy the filtered items to the release directory
foreach ($item in $filteredItems) {
    $destinationPath = Join-Path -Path $releasePath -ChildPath $item.Name
    if ($item.PSIsContainer) {
        Copy-Item -Path $item.FullName -Destination $destinationPath -Recurse -Force
    } else {
        Copy-Item -Path $item.FullName -Destination $destinationPath -Force
    }
}

Write-Output "Files and directories have been copied to $releasePath"
