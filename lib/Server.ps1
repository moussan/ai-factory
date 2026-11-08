# Local dashboard server (localhost only). Serves dashboard/ plus a small read-only API.

$script:Mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
    '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
}

function New-KitSessionToken {
    $b = New-Object byte[] 24
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($b); $rng.Dispose()
    [Convert]::ToBase64String($b).Replace('+', '-').Replace('/', '_').TrimEnd('=')
}

function Send-KitResponse {
    param($Context, [string]$Body, [int]$Status = 200, [string]$Type = 'application/json; charset=utf-8', [byte[]]$Bytes)
    if (-not $Bytes) { $Bytes = [Text.Encoding]::UTF8.GetBytes($Body) }
    $r = $Context.Response
    $r.StatusCode = $Status
    $r.ContentType = $Type
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.Headers.Add('X-Content-Type-Options', 'nosniff')
    $r.ContentLength64 = $Bytes.Length
    $r.OutputStream.Write($Bytes, 0, $Bytes.Length)
}

function ConvertTo-KitJson { param($Object, [int]$Depth = 12) ConvertTo-Json -InputObject $Object -Depth $Depth -Compress }

function Start-KitServer {
    param([int]$Port, [string]$Root, [string]$SessionToken, [switch]$OpenBrowser)

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    $url = "http://localhost:$Port/"
    Write-Host ''
    Write-Host "  Dashboard running at $url   (Ctrl+C to stop)" -ForegroundColor Green
    if ($OpenBrowser) { try { Start-Process $url } catch { } }

    try {
        while ($listener.IsListening) {
            $task = $listener.GetContextAsync()
            while (-not $task.Wait(500)) { }   # short waits so Ctrl+C is honoured
            $ctx = $task.Result
            try { Invoke-KitRoute -Context $ctx -Root $Root -SessionToken $SessionToken }
            catch { try { Send-KitResponse -Context $ctx -Status 500 -Body (ConvertTo-KitJson @{ error = $_.Exception.Message }) } catch { } }
            finally { try { $ctx.Response.Close() } catch { } }
        }
    } finally { $listener.Stop(); $listener.Close() }
}

function Invoke-KitRoute {
    param($Context, [string]$Root, [string]$SessionToken)
    $req = $Context.Request
    $path = $req.Url.AbsolutePath

    # DNS-rebinding guard: only answer for localhost names.
    if ($req.Url.Host -ne 'localhost' -and $req.Url.Host -ne '127.0.0.1') {
        Send-KitResponse -Context $Context -Status 403 -Body '{"error":"forbidden"}'; return
    }

    if ($path.StartsWith('/api/')) {
        if ($req.Headers['X-Kit-Token'] -ne $SessionToken) {
            Send-KitResponse -Context $Context -Status 401 -Body '{"error":"bad session token"}'; return
        }
        switch ($path) {
            '/api/data' {
                if ($script:KitData) { Send-KitResponse -Context $Context -Body (ConvertTo-KitJson $script:KitData 14) }
                else { Send-KitResponse -Context $Context -Status 404 -Body '{"error":"no data yet"}' }
                return
            }
            '/api/refresh' {
                if ($req.HttpMethod -ne 'POST') { Send-KitResponse -Context $Context -Status 405 -Body '{}'; return }
                Invoke-KitCollection
                Send-KitResponse -Context $Context -Body '{"ok":true}'; return
            }
            '/api/query' {
                $target = $req.QueryString['target']
                $q = $req.QueryString['path']
                if (-not $q -or -not $q.StartsWith('/')) { Send-KitResponse -Context $Context -Status 400 -Body '{"error":"path must start with /"}'; return }
                if (-not (Test-KitSignedIn $(if ($target -eq 'arm') { 'arm' } else { 'graph' }))) {
                    Send-KitResponse -Context $Context -Status 400 -Body (ConvertTo-KitJson @{ error = "Not signed in to $target" }); return
                }
                $follow = $req.QueryString['all'] -eq '1'
                if ($target -eq 'arm') {
                    $res = if ($follow) { @{ value = @(Invoke-Arm -Path $q -All) } } else { Invoke-Arm -Path $q }
                } else {
                    $beta = ($target -eq 'graph-beta')
                    if ($q -match '^/reports/.*get[A-Za-z0-9]+\(') {
                        $res = @{ csv = (Invoke-Graph -Path $q -Raw -Beta:$beta) }
                    } elseif ($follow) {
                        $res = @{ value = @(Invoke-Graph -Path $q -All -Beta:$beta -Eventual -Max 5000) }
                    } else {
                        $res = Invoke-Graph -Path $q -Beta:$beta -Eventual
                    }
                }
                if ($res -is [string]) { $res = @{ raw = $res } }
                Send-KitResponse -Context $Context -Body (ConvertTo-KitJson $res 14); return
            }
            '/api/update-check' { Send-KitResponse -Context $Context -Body (ConvertTo-KitJson (Test-KitUpdate $script:KitConfig)); return }
            '/api/update' {
                if ($req.HttpMethod -ne 'POST') { Send-KitResponse -Context $Context -Status 405 -Body '{}'; return }
                $msg = Update-Kit $script:KitConfig
                Send-KitResponse -Context $Context -Body (ConvertTo-KitJson @{ message = $msg }); return
            }
            default { Send-KitResponse -Context $Context -Status 404 -Body '{"error":"unknown endpoint"}'; return }
        }
    }

    # Static files from dashboard/
    $rel = if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
        Send-KitResponse -Context $Context -Status 404 -Type 'text/plain' -Body 'not found'; return
    }
    $ext = [IO.Path]::GetExtension($full).ToLower()
    $type = if ($script:Mime[$ext]) { $script:Mime[$ext] } else { 'application/octet-stream' }
    if ($rel -eq 'index.html') {
        $html = (Get-Content $full -Raw -Encoding UTF8).Replace('{{TOKEN}}', $SessionToken).Replace('{{MODE}}', $(if ($script:KitDemo) { 'demo' } else { 'live' }))
        Send-KitResponse -Context $Context -Type $type -Body $html
    } else {
        Send-KitResponse -Context $Context -Type $type -Bytes ([IO.File]::ReadAllBytes($full))
    }
}
