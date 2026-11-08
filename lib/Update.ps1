# Self-update: downloads the latest collectors, dashboard and scripts from GitHub.
# Never touches config.json, data/ or collectors/custom/.

function Get-KitGitHubHeaders {
    param($Config)
    $h = @{ 'User-Agent' = 'MS-AD-Kit'; Accept = 'application/vnd.github+json' }
    $tok = $env:MSADKIT_GH_TOKEN
    if (-not $tok -and $Config.update.token) { $tok = $Config.update.token }
    if ($tok) { $h['Authorization'] = "Bearer $tok" }
    $h
}

function Get-KitLocalVersion {
    $f = Join-Path $script:KitRoot 'version.json'
    if (Test-Path $f) { Get-Content $f -Raw | ConvertFrom-Json } else { [pscustomobject]@{ sha = ''; updated = '' } }
}

function Get-KitRemoteVersion {
    param($Config)
    $u = "https://api.github.com/repos/$($Config.update.repo)/commits/$($Config.update.branch)"
    $r = Invoke-RestMethod -Uri $u -Headers (Get-KitGitHubHeaders $Config)
    [pscustomobject]@{ sha = $r.sha; message = ($r.commit.message -split "`n")[0]; date = $r.commit.committer.date }
}

function Test-KitUpdate {
    param($Config)
    try {
        $l = Get-KitLocalVersion; $r = Get-KitRemoteVersion $Config
        [pscustomobject]@{ available = ($l.sha -ne $r.sha); local = $l.sha; remote = $r.sha; message = $r.message; error = $null }
    } catch {
        [pscustomobject]@{ available = $false; local = ''; remote = ''; message = ''; error = $_.Exception.Message }
    }
}

function Update-Kit {
    param($Config)
    $remote = Get-KitRemoteVersion $Config
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("msadkit-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $zip = Join-Path $tmp 'kit.zip'
        $zu = "https://api.github.com/repos/$($Config.update.repo)/zipball/$($Config.update.branch)"
        Invoke-WebRequest -Uri $zu -Headers (Get-KitGitHubHeaders $Config) -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $src = @(Get-ChildItem (Join-Path $tmp 'x') -Directory)[0].FullName

        # Updatable parts. Anything else (config.json, data/, collectors/custom) is left alone.
        foreach ($d in 'lib', 'dashboard') {
            if (Test-Path (Join-Path $src $d)) { Copy-Item (Join-Path $src $d) $script:KitRoot -Recurse -Force }
        }
        New-Item -ItemType Directory -Path (Join-Path $script:KitRoot 'collectors') -Force | Out-Null
        Get-ChildItem (Join-Path $src 'collectors') -Filter *.ps1 -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination (Join-Path $script:KitRoot 'collectors') -Force
        foreach ($f in 'MS-AD-Kit.ps1', 'Start-MSADKit.cmd', 'config.default.json', 'README.md') {
            if (Test-Path (Join-Path $src $f)) { Copy-Item (Join-Path $src $f) $script:KitRoot -Force }
        }
        @{ sha = $remote.sha; updated = (Get-Date).ToString('s'); message = $remote.message } |
            ConvertTo-Json | Set-Content (Join-Path $script:KitRoot 'version.json') -Encoding UTF8
        "Updated to $($remote.sha.Substring(0,7)) - $($remote.message). Restart the tool to use it."
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
