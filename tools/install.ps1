param([Parameter(Mandatory=$true)][string]$AddOnsPath)
$ErrorActionPreference='Stop'
function Get-PackageFilePath([string]$Root,[string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)) { throw 'Receipt/source path must be relative.' }
    $resolved=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $resolved.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'File path escaped package.' }
    return $resolved
}
function Assert-NoReparsePath([string]$Root,[string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($current,$Root,[StringComparison]::OrdinalIgnoreCase) -and
        -not $current.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped installation/source root.' }
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked installation/source path is not supported: $current" }
        }
        if ([string]::Equals($current,$Root,[StringComparison]::OrdinalIgnoreCase)) { break }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Assert-ExpectedFile([string]$Root,[string]$Path,[string]$ExpectedHash) {
    Assert-NoReparsePath $Root $Path
    if (Test-Path -LiteralPath $Path) {
        if ([string]::IsNullOrEmpty($ExpectedHash) -or (Get-FileHash -LiteralPath $Path).Hash -ne $ExpectedHash) {
            throw "Installed file was modified or is unmanaged: $Path"
        }
    }
}
function Add-LoadedSource([string]$Path,[string]$PackageRoot,[hashtable]$Loaded) {
    $fullPath=[IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($PackageRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Runtime load path escaped package.' }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing runtime load reference: $fullPath" }
    if ([IO.Path]::GetExtension($fullPath) -notin @('.lua','.xml')) { throw 'Runtime load reference must be Lua or XML.' }
    if ($Loaded.ContainsKey($fullPath)) { return }
    $Loaded[$fullPath]=$true
    if ([IO.Path]::GetExtension($fullPath) -eq '.xml') {
        $settings=New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create($fullPath,$settings)
        try { $document=New-Object System.Xml.XmlDocument;$document.Load($reader) }
        finally { $reader.Dispose() }
        foreach ($element in $document.SelectNodes('//*')) {
            if ($element.LocalName -in @('Script','Include') -and $element.HasAttribute('file')) {
                $reference=$element.GetAttribute('file')
                if ([IO.Path]::IsPathRooted($reference)) { throw 'Runtime load path must be relative.' }
                Add-LoadedSource (Join-Path (Split-Path $fullPath -Parent) $reference) $PackageRoot $Loaded
            }
        }
    }
}
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\addon'))
$targetRoot=(Resolve-Path -LiteralPath $AddOnsPath).Path
if ((Split-Path $targetRoot -Leaf) -ne 'AddOns') { throw 'Target must be an AddOns directory.' }
Assert-NoReparsePath $sourceRoot $sourceRoot
Assert-NoReparsePath $targetRoot $targetRoot
$mainToc=Join-Path $sourceRoot 'LycheeTalent\LycheeTalent.toc'
Assert-NoReparsePath $sourceRoot $mainToc
$releaseVersion=((Get-Content -LiteralPath $mainToc | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ','').Trim()
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid main addon version.' }
$packages=@(Get-ChildItem -LiteralPath $sourceRoot -Directory | Where-Object Name -Match '^LycheeTalent(_Data_[A-Z]+)?$')
if ($packages.Count -eq 0) { throw 'No packages found.' }
$plans=@()
foreach ($package in $packages) {
    Assert-NoReparsePath $sourceRoot $package.FullName
    foreach ($item in Get-ChildItem -LiteralPath $package.FullName -Force -Recurse) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked source path is not supported: $($item.FullName)" }
    }
    $destination=[IO.Path]::GetFullPath((Join-Path $targetRoot $package.Name))
    if (-not $destination.StartsWith($targetRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped AddOns root.' }
    Assert-NoReparsePath $targetRoot $destination
    $receiptPath=Join-Path $destination 'lychee-talent.install.json'
    $known=@{};$obsolete=@()
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath $receiptPath)) { throw "Existing unmanaged package: $($package.Name)" }
        Assert-NoReparsePath $targetRoot $receiptPath
        $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        if ($receipt.package -ne $package.Name -or $null -eq $receipt.files) { throw "Invalid install receipt: $($package.Name)" }
        foreach ($entry in $receipt.files) {
            $installed=Get-PackageFilePath $destination $entry.path
            if ($known.ContainsKey($installed) -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid or duplicate install receipt entry.' }
            $known[$installed]=$entry.sha256
            Assert-ExpectedFile $targetRoot $installed $entry.sha256
            $sourcePath=Get-PackageFilePath $package.FullName $entry.path
            if (-not (Test-Path -LiteralPath $sourcePath)) { $obsolete+=@{path=$installed;sha256=$entry.sha256} }
        }
    }
    $loaded=@{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $package.FullName ($package.Name+'.toc')) -Encoding UTF8) {
        $reference=$line.Trim()
        if ($reference -and -not $reference.StartsWith('#')) {
            Add-LoadedSource (Get-PackageFilePath $package.FullName $reference) $package.FullName $loaded
        }
    }
    $copies=@()
    foreach ($file in Get-ChildItem -LiteralPath $package.FullName -File -Recurse -Force) {
        $isNotice=$package.Name -eq 'LycheeTalent' -and $file.DirectoryName -eq $package.FullName -and $file.Name -in @('LICENSE','THIRD_PARTY_NOTICES.md')
        $isLibraryLock=$file.FullName -eq (Join-Path $sourceRoot 'LycheeTalent\Libs\LycheeUI\.lock')
        if ($file.Extension -notin @('.lua','.toc','.tga','.xml') -and -not $isNotice -and -not $isLibraryLock) { throw "Unexpected install source file: $($file.FullName)" }
        if ($file.Extension -in @('.lua','.xml') -and -not $loaded.ContainsKey($file.FullName)) { throw "Runtime source is not loaded by TOC/XML: $($file.FullName)" }
        $relative=$file.FullName.Substring($package.FullName.Length+1)
        $target=Get-PackageFilePath $destination $relative
        Assert-NoReparsePath $targetRoot $target
        $sourceHash=(Get-FileHash -LiteralPath $file.FullName).Hash
        $expected=$known[$target]
        if (-not $expected -and (Test-Path -LiteralPath $target)) {
            if ((Get-FileHash -LiteralPath $target).Hash -ne $sourceHash) { throw "Unmanaged target collision: $($package.Name)/$relative" }
            $expected=$sourceHash
        }
        $copies+=@{source=$file.FullName;target=$target;path=$relative;sha256=$sourceHash;previous=$expected}
    }
    $version=((Get-Content -LiteralPath (Join-Path $package.FullName ($package.Name+'.toc')) | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ','').Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid package version: $($package.Name)" }
    if ($version -ne $releaseVersion) { throw "Package version differs from main addon: $($package.Name)" }
    $plans+=@{name=$package.Name;destination=$destination;receipt=$receiptPath;copies=$copies;obsolete=$obsolete;version=$version}
}
$fileCount=0
foreach ($plan in $plans) {
    New-Item -ItemType Directory -Path $plan.destination -Force | Out-Null
    foreach ($entry in $plan.obsolete) {
        Assert-ExpectedFile $targetRoot $entry.path $entry.sha256
        if (Test-Path -LiteralPath $entry.path) {
            Remove-Item -LiteralPath $entry.path
        }
    }
    $files=@()
    foreach ($entry in $plan.copies) {
        Assert-ExpectedFile $targetRoot $entry.target $entry.previous
        Assert-NoReparsePath $sourceRoot $entry.source
        if ((Get-FileHash -LiteralPath $entry.source).Hash -ne $entry.sha256) { throw "Source changed after preflight: $($entry.path)" }
        New-Item -ItemType Directory -Path (Split-Path $entry.target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $entry.source -Destination $entry.target -Force
        if ((Get-FileHash -LiteralPath $entry.target).Hash -ne $entry.sha256) { throw "Copy mismatch: $($entry.path)" }
        $files+=@{path=$entry.path;sha256=$entry.sha256};$fileCount++
    }
    Assert-NoReparsePath $targetRoot $plan.receipt
    @{package=$plan.name;version=$plan.version;files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $plan.receipt -Encoding utf8
}
[pscustomobject]@{Packages=$packages.Count;VerifiedFiles=$fileCount;Destination=$targetRoot}
