Powershell as admin

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iwr https://community.chocolatey.org/install.ps1 -UseBasicParsing | iex

choco --version
choco install velero



###### working command ########

$version = "v1.15.0"
$url = "https://github.com"

# Use wget (Invoke-WebRequest) to download the file
wget $url -OutFile "velero.tar.gz"

tar -xvf velero.tar.gz











# 1. Define variables
$version = "v1.15.2"  # You can check for the latest at https://github.com/vmware-tanzu/velero/releases
$installDir = "D:\Velero"
$zipPath = "$env:TEMP\velero.zip"
$url = "https://github.com"

# 2. Create the target directory if it doesn't exist
if (!(Test-Path $installDir)) {
    New-Item -ItemType Directory -Force -Path $installDir
}

# 3. Download the Velero release (Note: GitHub uses .tar.gz even for Windows releases)
Invoke-WebRequest -Uri $url -OutFile $zipPath

# 4. Extract the files
# Note: Modern Windows 'Expand-Archive' may not support .tar.gz. 
# If you have 'tar' installed (included in Windows 10/11), use this:
tar -xzf $zipPath -C $installDir --strip-components 1

# 5. Verify the installation
& "$installDir\velero.exe" version --client-only

# 6. Cleanup
Remove-Item $zipPath
