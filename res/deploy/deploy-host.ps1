<#
.SYNOPSIS
  Silent install of the host-only RustDesk MSI, optional permanent password, prints the ID,
  and optionally registers the device in an address book of the free API server
  (lejianwen/rustdesk-api).

.DESCRIPTION
  Address book registration logs in with a dedicated, non-admin "generic" account and adds
  this device to that account's personal address book, or to a shared collection
  (address book "folder") the account can write to (-AbCollection).
  The account's credentials are only used by this script; they are never stored on the host.

.EXAMPLE
  # As administrator, install only:
  .\deploy-host.ps1 -Msi .\rustdesk-host-1.5.3-x86_64.msi -Password 'S3cret!Long'

.EXAMPLE
  # Install + register in the "Clients" collection with a tag:
  .\deploy-host.ps1 -Msi .\rustdesk-host-1.5.3-x86_64.msi -Password 'S3cret!Long' `
      -ApiServer https://rustdesk-api.example.com -AbUser host-generique -AbPassword 'xxx' `
      -AbCollection Clients -Tags 'Site-Paris'
#>
param(
    [Parameter(Mandatory = $true)][string]$Msi,
    [string]$Password = "",
    [string]$InstallDir = "$env:ProgramFiles\RustDesk",
    # Address book registration (all optional)
    [string]$ApiServer = "",
    [string]$AbUser = "",
    [string]$AbPassword = "",
    [string]$AbCollection = "",
    [string[]]$Tags = @(),
    [string]$Alias = $env:COMPUTERNAME
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

if (-not ($ApiServer -and $AbUser -and $AbPassword)) { return }
if (-not $id) { Write-Warning "No ID yet, address book registration skipped."; return }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$api = $ApiServer.TrimEnd('/')
$token = $null
try {
    $login = Invoke-RestMethod -Method Post -Uri "$api/api/login" -ContentType "application/json" -Body (@{
            username   = $AbUser
            password   = $AbPassword
            id         = $id
            type       = "account"
            deviceInfo = @{ os = "windows"; type = "client"; name = $env:COMPUTERNAME }
        } | ConvertTo-Json)
    if (-not $login.access_token) { throw "login failed: $($login | ConvertTo-Json -Compress)" }
    $token = $login.access_token
    $h = @{ Authorization = "Bearer $token" }

    if ($AbCollection) {
        $profiles = Invoke-RestMethod -Method Post -Uri "$api/api/ab/shared/profiles?current=1&pageSize=100" -Headers $h
        $ab = $profiles.data | Where-Object { $_.name -eq $AbCollection } | Select-Object -First 1
        if (-not $ab) { throw "address book collection '$AbCollection' not found or not accessible by $AbUser" }
        $guid = $ab.guid
    } else {
        $personal = Invoke-RestMethod -Method Post -Uri "$api/api/ab/personal" -Headers $h
        if (-not $personal.guid) { throw "personal address book is disabled on the API server" }
        $guid = $personal.guid
    }

    foreach ($t in $Tags) {
        try { Invoke-RestMethod -Method Post -Uri "$api/api/ab/tag/add/$guid" -Headers $h -ContentType "application/json" -Body (@{ name = $t; color = 0 } | ConvertTo-Json) | Out-Null } catch {}
    }
    $res = Invoke-RestMethod -Method Post -Uri "$api/api/ab/peer/add/$guid" -Headers $h -ContentType "application/json" -Body (@{
            id    = $id
            alias = $Alias
            tags  = @($Tags)
        } | ConvertTo-Json)
    if ($res -and $res.error) { throw $res.error }
    Write-Host "Device $id added to address book '$(if ($AbCollection) { $AbCollection } else { $AbUser })'."
} catch {
    Write-Warning "Address book registration failed: $_"
} finally {
    if ($token) {
        try { Invoke-RestMethod -Method Post -Uri "$api/api/logout" -Headers @{ Authorization = "Bearer $token" } | Out-Null } catch {}
    }
}
