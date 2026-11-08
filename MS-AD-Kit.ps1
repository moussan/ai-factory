<#
.SYNOPSIS
  MS-AD-Kit - sign in with an admin account, query a Microsoft tenant, see it on a live dashboard.

.EXAMPLE
  .\MS-AD-Kit.ps1                 # sign in, collect, open dashboard
  .\MS-AD-Kit.ps1 -Azure          # also sign in to Azure (subscriptions / resources)
  .\MS-AD-Kit.ps1 -Demo           # sample data, no sign-in
  .\MS-AD-Kit.ps1 -Cached         # reopen the last collected data without signing in
  .\MS-AD-Kit.ps1 -Export r.html  # write a single shareable HTML file and exit
  .\MS-AD-Kit.ps1 -Update         # pull the newest collectors / dashboard from GitHub
#>
[CmdletBinding()]
param(
    [string]$TenantId,
    [switch]$Azure,
    [switch]$Demo,
    [switch]$Cached,
    [string]$Export,
    [string[]]$Only,
    [int]$Port = 0,
    [switch]$NoBrowser,
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script:KitRoot = $PSScriptRoot
$script:KitDemo = [bool]$Demo
$script:KitData = $null

foreach ($f in 'Auth', 'Api', 'Server', 'Update') { . (Join-Path $PSScriptRoot "lib\$f.ps1") }

# ---- config (user copy is never overwritten by updates) ---------------------------------
$cfgPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $cfgPath)) { Copy-Item (Join-Path $PSScriptRoot 'config.default.json') $cfgPath }
$script:KitConfig = Get-Content $cfgPath -Raw | ConvertFrom-Json
if (-not $Port) { $Port = [int]$script:KitConfig.port }

Write-Host ''
Write-Host '  MS-AD-Kit - Microsoft tenant explorer' -ForegroundColor White
$lv = Get-KitLocalVersion
Write-Host ("  version: " + $(if ($lv.sha) { $lv.sha.Substring(0, 7) } else { 'local' })) -ForegroundColor DarkGray

if ($Update) {
    try { Update-Kit $script:KitConfig } catch { Write-Host "  Update failed: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
    exit 0
}

# ---- collection -------------------------------------------------------------------------
function Get-KitCollectors {
    $files = @(Get-ChildItem (Join-Path $PSScriptRoot 'collectors') -Filter *.ps1 -File -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem (Join-Path $PSScriptRoot 'collectors\custom') -Filter *.ps1 -File -ErrorAction SilentlyContinue)
    $defs = foreach ($f in $files) {
        try { & $f.FullName } catch { Write-Host "  ! cannot load $($f.Name): $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    @($defs | Where-Object { $_ -and $_.Id } | Sort-Object { [int]$_.Order })
}

function Invoke-KitCollection {
    if (-not $script:KitDemo -and -not (Test-KitSignedIn 'graph')) { throw 'Not signed in (cached/demo view). Restart the tool without -Cached to refresh.' }
    $tid = $null; $user = $null
    if (Test-KitSignedIn 'graph') { $t = Get-KitToken 'graph'; $tid = $t.tenantId; $user = $t.user }
    $results = @()
    $defs = Get-KitCollectors
    if ($Only) { $defs = @($defs | Where-Object { $Only -contains $_.Id }) }
    $i = 0
    foreach ($d in $defs) {
        $i++
        $label = '{0,2}/{1} {2}' -f $i, $defs.Count, $d.Title
        $res = [ordered]@{
            id = $d.Id; title = $d.Title; icon = $d.Icon; order = [int]$d.Order; target = $d.Target
            status = 'ok'; error = $null; ms = 0; summary = @(); charts = @(); tables = @(); findings = @()
        }
        if (-not (Test-KitSignedIn $d.Target)) {
            $res.status = 'skipped'; $res.error = "Not signed in to $($d.Target) (use -Azure for Azure collectors)."
            Write-Host "  - $label (skipped)" -ForegroundColor DarkGray
        } else {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                $out = & $d.Run
                foreach ($k in 'summary', 'charts', 'tables', 'findings') { if ($out.$k) { $res[$k] = @($out.$k) } }
                foreach ($tb in $res.tables) { if (@($tb.rows).Count -gt $script:KitConfig.maxTableRows) { $tb.rows = @($tb.rows | Select-Object -First $script:KitConfig.maxTableRows); $tb.truncated = $true } }
                Write-Host "  + $label" -ForegroundColor Green
            } catch {
                $res.status = 'error'; $res.error = $_.Exception.Message
                Write-Host "  x $label - $($res.error)" -ForegroundColor Yellow
            }
            $res.ms = [int]$sw.ElapsedMilliseconds
        }
        $results += [pscustomobject]$res
    }
    $script:KitData = @{
        generated  = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
        tenantId   = $tid
        user       = $user
        azureUser  = $(if (Test-KitSignedIn 'arm') { (Get-KitToken 'arm').user } else { $null })
        collectors = $results
    }
    $dataDir = Join-Path $PSScriptRoot 'data'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    ConvertTo-KitJson $script:KitData 14 | Set-Content (Join-Path $dataDir 'last.json') -Encoding UTF8
}

# ---- sign in + run ----------------------------------------------------------------------
$tenant = if ($TenantId) { $TenantId } elseif ($script:KitConfig.tenantId) { $script:KitConfig.tenantId } else { 'organizations' }

try {
    if ($Demo) {
        Write-Host '  Demo mode - sample data, no sign-in.' -ForegroundColor Yellow
    } elseif ($Cached) {
        $last = Join-Path $PSScriptRoot 'data\last.json'
        if (-not (Test-Path $last)) { throw 'No cached data yet. Run once without -Cached.' }
        $script:KitData = Get-Content $last -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "  Using cached data from $($script:KitData.generated)." -ForegroundColor Yellow
    } else {
        Write-Host '  Sign in with an admin account (Global Reader or higher gives the fullest picture).'
        Connect-KitDevice -Name 'graph' -ClientId $script:KitConfig.graph.clientId -Scope $script:KitConfig.graph.scopes -Tenant $tenant
        if ($Azure -or $script:KitConfig.azure.enabled) {
            $azTenant = if ((Get-KitToken 'graph').tenantId) { (Get-KitToken 'graph').tenantId } else { $tenant }
            Connect-KitDevice -Name 'arm' -ClientId $script:KitConfig.azure.clientId -Scope $script:KitConfig.azure.scopes -Tenant $azTenant
        }
        Write-Host ''
        Write-Host '  Collecting...'
        Invoke-KitCollection
    }
} catch {
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ---- export or serve --------------------------------------------------------------------
if ($Export) {
    $dash = Join-Path $PSScriptRoot 'dashboard'
    $html = Get-Content (Join-Path $dash 'index.html') -Raw -Encoding UTF8
    $css = Get-Content (Join-Path $dash 'style.css') -Raw -Encoding UTF8
    $js = (Get-Content (Join-Path $dash 'app.js') -Raw -Encoding UTF8)
    $json = (ConvertTo-KitJson $script:KitData 14).Replace('</', '<\/')
    $demoJs = ''
    if ($Demo) { $demoJs = '<script>' + (Get-Content (Join-Path $dash 'demo.js') -Raw -Encoding UTF8) + '</script>' }
    $html = $html.Replace('<link rel="stylesheet" href="style.css">', "<style>$css</style>")
    $html = $html.Replace('<script src="demo.js"></script>', $demoJs)
    $html = $html.Replace('<script src="app.js"></script>', "<script>window.__KIT_DATA__=$json;</script><script>$js</script>")
    $html = $html.Replace('{{TOKEN}}', '').Replace('{{MODE}}', 'static')
    [IO.File]::WriteAllText((Join-Path (Get-Location) $Export), $html, (New-Object Text.UTF8Encoding($false)))
    Write-Host "  Exported to $Export" -ForegroundColor Green
    exit 0
}

$token = New-KitSessionToken
Start-KitServer -Port $Port -Root (Join-Path $PSScriptRoot 'dashboard') -SessionToken $token -OpenBrowser:(-not $NoBrowser)
