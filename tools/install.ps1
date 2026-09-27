param([Parameter(Mandatory=$true)][string]$AddOnsPath)
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\addon'))
$targetRoot=(Resolve-Path -LiteralPath $AddOnsPath).Path
if ((Split-Path $targetRoot -Leaf) -ne 'AddOns') { throw 'Target must be an AddOns directory.' }
$packages=@(Get-ChildItem -LiteralPath $sourceRoot -Directory | Where-Object Name -Match '^LycheeTalent(_Data_[A-Z]+)?$')
if ($packages.Count -eq 0) { throw 'No packages found.' }
foreach ($package in $packages) {
    $destination=[IO.Path]::GetFullPath((Join-Path $targetRoot $package.Name))
    if (-not $destination.StartsWith($targetRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped AddOns root.' }
    $receiptPath=Join-Path $destination 'lychee-talent.install.json'
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath $receiptPath)) { throw "Existing unmanaged package: $($package.Name)" }
        $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach ($entry in $receipt.files) {
            $installed=Join-Path $destination $entry.path
            if ((Test-Path -LiteralPath $installed) -and (Get-FileHash -LiteralPath $installed).Hash -ne $entry.sha256) {
                throw "Installed file was modified: $($package.Name)/$($entry.path)"
            }
        }
    }
}
$fileCount=0
foreach ($package in $packages) {
    $destination=Join-Path $targetRoot $package.Name
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $receiptPath=Join-Path $destination 'lychee-talent.install.json'
    if (Test-Path -LiteralPath $receiptPath) {
        $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach ($entry in $receipt.files) {
            $obsolete=[IO.Path]::GetFullPath((Join-Path $destination $entry.path))
            if (-not $obsolete.StartsWith($destination.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Receipt path escaped package.' }
            if (-not (Test-Path -LiteralPath (Join-Path $package.FullName $entry.path)) -and (Test-Path -LiteralPath $obsolete)) {
                Remove-Item -LiteralPath $obsolete
            }
        }
    }
    $files=@()
    foreach ($file in Get-ChildItem -LiteralPath $package.FullName -File -Recurse) {
        $relative=$file.FullName.Substring($package.FullName.Length+1)
        $target=Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $sourceHash=(Get-FileHash -LiteralPath $file.FullName).Hash
        if ((Get-FileHash -LiteralPath $target).Hash -ne $sourceHash) { throw "Copy mismatch: $relative" }
        $files+=@{path=$relative;sha256=$sourceHash};$fileCount++
    }
    @{package=$package.Name;version='1.0.0';files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'lychee-talent.install.json') -Encoding utf8
}
[pscustomobject]@{Packages=$packages.Count;VerifiedFiles=$fileCount;Destination=$targetRoot}
