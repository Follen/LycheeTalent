param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\addon'))
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
if ($outputRoot.Equals($sourceRoot,[StringComparison]::OrdinalIgnoreCase) -or $outputRoot.StartsWith($sourceRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside addon sources.' }
# Inspect directories before recursion so a junction cannot pull external files into a release.
$pendingDirectories=New-Object 'System.Collections.Generic.Stack[string]'
$pendingDirectories.Push($sourceRoot)
while ($pendingDirectories.Count) {
    $directory=$pendingDirectories.Pop()
    if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in addon sources: $directory" }
    foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in addon sources: $($item.FullName)" }
        if ($item.PSIsContainer) { $pendingDirectories.Push($item.FullName) }
    }
}

function Add-LoadedSource([string]$LoadPath,[string]$PackageRoot,[hashtable]$Loaded) {
    $fullPath=[IO.Path]::GetFullPath($LoadPath)
    if (-not $fullPath.StartsWith($PackageRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Load path escaped package: $LoadPath" }
    if ([IO.Path]::GetExtension($fullPath) -notin @('.lua','.xml')) { throw "Unsupported runtime load reference: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing runtime load reference: $fullPath" }
    if ($Loaded.ContainsKey($fullPath)) { return }
    $Loaded[$fullPath]=$true
    if ([IO.Path]::GetExtension($fullPath) -eq '.xml') {
        $settings=New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create($fullPath,$settings)
        try {
            $document=New-Object System.Xml.XmlDocument
            $document.Load($reader)
        } finally { $reader.Dispose() }
        foreach ($element in $document.SelectNodes('//*')) {
            if ($element.LocalName -in @('Script','Include') -and $element.HasAttribute('file')) {
                Add-LoadedSource (Join-Path (Split-Path $fullPath -Parent) $element.GetAttribute('file')) $PackageRoot $Loaded
            }
        }
    }
}
$toc=Get-Content -LiteralPath (Join-Path $sourceRoot 'LycheeTalent\LycheeTalent.toc')
$version=($toc | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ',' '
$version=$version.Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid addon version.' }
$packages=@(Get-ChildItem -LiteralPath $sourceRoot -Directory | Where-Object Name -Match '^LycheeTalent(_Data_[A-Z]+)?$')
$libraryRoot=Join-Path $sourceRoot 'LycheeTalent\Libs\LycheeUI'
$libraryLockPath=Join-Path $libraryRoot '.lock'
if (-not (Test-Path -LiteralPath $libraryLockPath -PathType Leaf)) { throw 'Missing embedded LycheeUI manifest.' }
$libraryLock=Get-Content -LiteralPath $libraryLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($libraryLock.library -ne 'LycheeUI' -or $libraryLock.status -ne 'frozen') { throw 'Embedded LycheeUI must have a frozen manifest.' }
$runtimePaths=@($libraryLock.runtimeFiles | ForEach-Object { $_.path.Replace('\','/') })
$libraryFiles=@(Get-ChildItem -LiteralPath $libraryRoot -File -Recurse | Where-Object FullName -NE $libraryLockPath | ForEach-Object {
    $_.FullName.Substring($libraryRoot.Length+1).Replace('\','/')
})
if ($runtimePaths.Count -ne $libraryFiles.Count -or (Compare-Object $runtimePaths $libraryFiles)) { throw 'Embedded LycheeUI file set differs from its manifest.' }
foreach ($entry in $libraryLock.runtimeFiles) {
    $runtimePath=[IO.Path]::GetFullPath((Join-Path $libraryRoot $entry.path))
    if (-not $runtimePath.StartsWith($libraryRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'LycheeUI manifest path escaped library.' }
    if ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Embedded LycheeUI file changed: $($entry.path)" }
}
$expected=@{}
foreach ($package in $packages) {
    $packageToc=Join-Path $package.FullName ($package.Name+'.toc')
    $packageVersion=((Get-Content -LiteralPath $packageToc | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ','').Trim()
    if ($packageVersion -ne $version) { throw "Package version mismatch: $($package.Name)" }
    $loaded=@{}
    foreach ($line in Get-Content -LiteralPath $packageToc -Encoding UTF8) {
        $reference=$line.Trim()
        if ($reference -and -not $reference.StartsWith('#')) { Add-LoadedSource (Join-Path $package.FullName $reference) $package.FullName $loaded }
    }
    foreach ($file in Get-ChildItem -LiteralPath $package.FullName -Recurse -File) {
        $isNotice=$package.Name -eq 'LycheeTalent' -and $file.DirectoryName -eq $package.FullName -and $file.Name -in @('LICENSE','THIRD_PARTY_NOTICES.md')
        $isLibraryLock=$file.FullName -eq $libraryLockPath
        if ($file.Extension -notin @('.lua','.toc','.tga','.xml') -and -not $isNotice -and -not $isLibraryLock) { throw "Unexpected release file: $($file.Name)" }
        if ($file.Extension -in @('.lua','.xml') -and -not $loaded.ContainsKey($file.FullName)) { throw "Runtime file is not loaded by package TOC/XML: $($file.FullName)" }
        $relative=$file.FullName.Substring($sourceRoot.Length+1).Replace('\','/')
        $expected[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}
if (-not $expected.ContainsKey('LycheeTalent/LycheeTalent.toc')) { throw 'Missing main addon.' }
foreach ($notice in @('LICENSE','THIRD_PARTY_NOTICES.md')) {
    $rootNotice=Join-Path (Split-Path $sourceRoot -Parent) $notice
    if (-not $expected.ContainsKey('LycheeTalent/'+$notice) -or $expected['LycheeTalent/'+$notice] -ne (Get-FileHash -LiteralPath $rootNotice -Algorithm SHA256).Hash) { throw "Missing or stale release notice: $notice" }
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$zipPath=Join-Path $outputRoot "LycheeTalent-$version.zip"
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipStream=[IO.File]::Open($zipPath,[IO.FileMode]::Create)
try {
    $writer=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        # Use ZIP path separators consistently; Windows PowerShell Compress-Archive writes backslashes.
        foreach ($name in @($expected.Keys | Sort-Object)) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($writer,(Join-Path $sourceRoot $name),$name,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $writer.Dispose() }
} finally { $zipStream.Dispose() }
$archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $seen=@{}
    foreach ($entry in $archive.Entries) {
        if (-not $entry.Name) { continue }
        $name=$entry.FullName
        if ($name.Contains('\')) { throw "Archive path must use forward slashes: $name" }
        if (-not $expected.ContainsKey($name) -or $seen.ContainsKey($name)) { throw "Unexpected archive entry: $name" }
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $stream.Dispose();$sha.Dispose() }
        if ($hash -ne $expected[$name]) { throw "Archive content mismatch: $name" }
        $seen[$name]=$true
    }
    if ($seen.Count -ne $expected.Count) { throw 'Archive is missing files.' }
} finally { $archive.Dispose() }
$digest=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zipPath+'.sha256') -Value ($digest+'  '+[IO.Path]::GetFileName($zipPath)) -Encoding ascii
[pscustomobject]@{Path=$zipPath;Packages=$packages.Count;VerifiedFiles=$expected.Count;SHA256=$digest}
