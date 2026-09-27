param([string]$OutputDirectory=(Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\addon'))
$outputRoot=[IO.Path]::GetFullPath($OutputDirectory)
if ($outputRoot.StartsWith($sourceRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside addon sources.' }
$toc=Get-Content -LiteralPath (Join-Path $sourceRoot 'LycheeTalent\LycheeTalent.toc')
$version=($toc | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ',' '
$version=$version.Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid addon version.' }
$packages=@(Get-ChildItem -LiteralPath $sourceRoot -Directory | Where-Object Name -Match '^LycheeTalent(_Data_[A-Z]+)?$')
$expected=@{}
foreach ($package in $packages) {
    $packageToc=Join-Path $package.FullName ($package.Name+'.toc')
    $packageVersion=((Get-Content -LiteralPath $packageToc | Where-Object { $_ -match '^## Version: ' }) -replace '^## Version: ','').Trim()
    if ($packageVersion -ne $version) { throw "Package version mismatch: $($package.Name)" }
    foreach ($file in Get-ChildItem -LiteralPath $package.FullName -Recurse -File) {
        $isNotice=$package.Name -eq 'LycheeTalent' -and $file.DirectoryName -eq $package.FullName -and $file.Name -in @('LICENSE','THIRD_PARTY_NOTICES.md')
        if ($file.Extension -notin @('.lua','.toc','.tga') -and -not $isNotice) { throw "Unexpected release file: $($file.Name)" }
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
Compress-Archive -LiteralPath @($packages.FullName) -DestinationPath $zipPath -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $seen=@{}
    foreach ($entry in $archive.Entries) {
        if (-not $entry.Name) { continue }
        $name=$entry.FullName.Replace('\','/')
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
