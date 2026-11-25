param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputPath = [IO.Path]::GetFullPath($Output)
$work = Join-Path ([IO.Path]::GetTempPath()) ('tradocraft-build-' + [guid]::NewGuid())
$stage = Join-Path $work 'TradoCraft Demo'

function Expand-VerifiedZip($Url, $Hash, $Destination) {
    $zip = Join-Path $work ([IO.Path]::GetFileName($Url))
    curl.exe -fsSL --retry 3 --output $zip $Url
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $Hash) {
        throw "SHA-256 mismatch for $Url"
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $Destination
}

$smokeLogs = Join-Path $env:LOCALAPPDATA 'TradoCraft/Demo packaging smoke/logs'

function Invoke-DemoSmoke($Exe, [string[]]$Flags, [int]$ExpectedExit = 0) {
    Write-Host "Running demo check: $Flags (expected exit $ExpectedExit)"
    $process = Start-Process -FilePath $Exe -ArgumentList $Flags -PassThru
    if (!$process.WaitForExit(300000)) {
        $process.Kill()
        throw 'The native demo smoke test timed out.'
    }
    if ($process.ExitCode -ne $ExpectedExit) {
        throw "The native demo smoke test failed with exit code $($process.ExitCode)."
    }
}

New-Item -ItemType Directory -Force -Path $outputPath, $stage | Out-Null
try {
    Push-Location -LiteralPath $repo
    try {
        cargo build --locked --release -p tradocraft-api -p tradocraft-worker
        cargo test --locked --release -p tradocraft-core blob_store::tests
        Push-Location app
        try {
            flutter pub get
            flutter build windows --release "--build-name=$Version"
        } finally { Pop-Location }
    } finally { Pop-Location }

    $backend = New-Item -ItemType Directory -Path (Join-Path $stage 'backend')
    Copy-Item (Join-Path $repo 'target/release/tradocraft-api.exe') $backend
    Copy-Item (Join-Path $repo 'target/release/tradocraft-worker.exe') $backend
    Copy-Item (Join-Path $repo 'app/build/windows/x64/runner/Release') (Join-Path $stage 'app') -Recurse
    Copy-Item (Join-Path $repo 'templates') (Join-Path $stage 'templates') -Recurse
    Copy-Item (Join-Path $repo 'LICENSE') (Join-Path $stage 'LICENSE-TradoCraft.txt')
    Copy-Item (Join-Path $PSScriptRoot 'README.txt') $stage
    Copy-Item (Join-Path $PSScriptRoot 'Reset TradoCraft Demo.cmd') $stage

    Expand-VerifiedZip 'https://get.enterprisedb.com/postgresql/postgresql-16.16-2-windows-x64-binaries.zip' `
        'add1de261b150e6923266abee293f05050795e73f5356158aee4221a2170c073' (Join-Path $work 'pg')
    $pg = Join-Path $stage 'postgresql'
    New-Item -ItemType Directory -Path $pg | Out-Null
    foreach ($dir in 'bin', 'lib', 'share') {
        Copy-Item (Join-Path $work "pg/pgsql/$dir") $pg -Recurse
    }
    Get-ChildItem (Join-Path $work 'pg/pgsql') -File |
        Where-Object Name -Match 'license|notice|copyright' | Copy-Item -Destination $pg
    foreach ($ext in 'unaccent', 'pg_trgm') {
        if (!(Test-Path (Join-Path $pg "share/extension/$ext.control"))) {
            throw "PostgreSQL package is missing $ext."
        }
    }

    Expand-VerifiedZip 'https://github.com/typst/typst/releases/download/v0.15.1/typst-x86_64-pc-windows-msvc.zip' `
        '19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736' (Join-Path $work 'typst')
    $typst = Get-ChildItem (Join-Path $work 'typst') -Recurse -Filter typst.exe | Select-Object -First 1
    Copy-Item -LiteralPath $typst.DirectoryName -Destination (Join-Path $stage 'typst') -Recurse

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'Visual Studio with the x64 C++ build tools is required.' }
    $redist = Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory |
        Where-Object Name -Match '^\d+(\.\d+)+$' | Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    $crt = Get-ChildItem (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
        Select-Object -First 1
    foreach ($dir in 'app', 'backend', 'postgresql/bin', 'typst') {
        Copy-Item (Join-Path $crt.FullName '*.dll') (Join-Path $stage $dir)
    }

    $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $launcher = Join-Path $stage 'Start TradoCraft Demo.exe'
    & $csc /nologo /target:winexe /platform:x64 "/out:$launcher" /reference:System.Windows.Forms.dll `
        /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'DemoLauncher.cs')

    $zip = Join-Path $outputPath 'tradocraft-demo-windows-x64.zip'
    Compress-Archive -LiteralPath $stage -DestinationPath $zip -Force
    $smokeRoot = Join-Path $work 'Demo extracted'
    Expand-Archive -LiteralPath $zip -DestinationPath $smokeRoot
    $extracted = Join-Path $smokeRoot 'TradoCraft Demo'
    $smoke = Join-Path $extracted 'Smoke Demo.exe'
    Copy-Item -LiteralPath (Join-Path $extracted 'Start TradoCraft Demo.exe') -Destination $smoke
    try {
        $unsupported = New-Item -ItemType Directory -Path (Join-Path $work 'Démonstration')
        Copy-Item -LiteralPath $smoke -Destination $unsupported.FullName
        Invoke-DemoSmoke (Join-Path $unsupported.FullName 'Smoke Demo.exe') @('--smoke') 1
        $lastLaunch = Get-Content (Join-Path $smokeLogs 'launcher.log') -Tail 8
        if (!($lastLaunch -match 'Open the demo from a path containing only ASCII characters')) {
            throw 'The launcher did not explain the unsupported extraction path.'
        }
        Invoke-DemoSmoke $smoke @('--smoke', '--reset')
        Invoke-DemoSmoke $smoke @('--smoke')
        Invoke-DemoSmoke $smoke @('--smoke')
        Invoke-DemoSmoke $smoke @('--smoke', '--reset')
        if (Test-Path (Join-Path $env:LOCALAPPDATA 'TradoCraft/Demo packaging smoke/instance')) {
            throw 'Reset left the smoke-test instance behind.'
        }
    } catch {
        Get-ChildItem -LiteralPath $smokeLogs -Filter '*.log' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-Host "--- $($_.Name) ---"
                Get-Content -LiteralPath $_.FullName -Tail 40
            }
        throw
    } finally { Remove-Item -LiteralPath $smoke -Force }

    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
    if (!(Test-Path -LiteralPath $iscc)) { throw 'Inno Setup 6 is required to build the setup EXE.' }
    & $iscc "/DMyVersion=$Version" "/DBundleDir=$stage" "/O$outputPath" (Join-Path $PSScriptRoot 'DemoSetup.iss')
    $artifacts = 'tradocraft-demo-windows-x64.zip', 'tradocraft-demo-windows-x64-setup.exe'
    $artifacts | ForEach-Object {
        $hash = (Get-FileHash (Join-Path $outputPath $_) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $_"
    } | Set-Content (Join-Path $outputPath 'tradocraft-demo-windows-x64-sha256.txt') -Encoding ascii
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
