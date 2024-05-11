param($directory)

# Define the output variable to hold the combined content
$combinedContent = ""

# Get all files in the directory
$files = Get-ChildItem -Path $directory -File

# Loop through each file
foreach ($file in $files) {
    if ($file -like "*ps1") {
        # Read the content of the file
        $content = Get-Content -Path $file.FullName

        # Create a header with the file name
        $header = "`n`nFile: " + $file.Name + "`n`n"

        # Add the header and the content of the file to the combined string
        $combinedContent += $header + $content
    }
}

# Output the combined content
$combinedContent
