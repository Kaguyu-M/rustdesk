<#
.SYNOPSIS
  Silent install of the host-only RustDesk MSI, optional permanent password, prints the ID.
  Placing the device under an owner / in "Accessible devices" is done server side
  (see server-assign-peers.sh), so no account credentials are needed here.

.EXAMPLE
  # As administrator:
  .\deploy-host.ps1 -Msi .\rustdesk-host-1.5.3-x86_64.msi -Password 'S3cret!Long'
#>
param(
    [Parameter(Mandatory = $true)][string]$Msi,
    [string]$Password = "",
    [string]$InstallDir = "$env:ProgramFiles\RustDesk"
)
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script as administrator."
}

$msiPath = (Resolve-Path $Msi).Path
$log = Join-Path $env:TEMP "rustdesk-host-install.log"
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$log`"" -Wait -PassThru
if ($p.ExitCode -notin 0, 3010) { throw "msiexec failed ($($p.ExitCode)), see $log" }

$exe = Join-Path $InstallDir "rustdesk.exe"
for ($i = 0; $i -lt 30 -and -not (Get-Service -Name RustDesk -ErrorAction SilentlyContinue); $i++) { Start-Sleep 2 }
if (-not (Test-Path $exe)) { throw "rustdesk.exe not found in $InstallDir" }

if ($Password) {
    & $exe --password $Password | Out-Null
    Write-Host "Permanent password set."
}

$id = ""
for ($i = 0; $i -lt 15 -and -not $id; $i++) {
    $id = (& $exe --get-id | Out-String).Trim()
    if (-not $id) { Start-Sleep 2 }
}
Write-Host "RustDesk ID: $id"
