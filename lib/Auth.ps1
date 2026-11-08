# Authentication: OAuth2 device-code flow, no modules required.
# Tokens live in memory only (never written to disk).

$script:Tokens = @{}

function ConvertFrom-KitJwt {
    param([string]$Jwt)
    try {
        $p = $Jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
        while ($p.Length % 4) { $p += '=' }
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
    } catch { $null }
}

function Save-KitToken {
    param([string]$Name, $Response, [string]$ClientId, [string]$Tenant, [string]$Scope)
    $claims = $null
    if ($Response.id_token) { $claims = ConvertFrom-KitJwt $Response.id_token }
    $old = $script:Tokens[$Name]
    $script:Tokens[$Name] = @{
        access   = $Response.access_token
        refresh  = $(if ($Response.refresh_token) { $Response.refresh_token } elseif ($old) { $old.refresh } else { $null })
        expires  = (Get-Date).AddSeconds([int]$Response.expires_in)
        clientId = $ClientId
        tenant   = $Tenant
        scope    = $Scope
        user     = $(if ($claims) { $claims.preferred_username } elseif ($old) { $old.user } else { $null })
        tenantId = $(if ($claims) { $claims.tid } elseif ($old) { $old.tenantId } else { $null })
    }
}

function Connect-KitDevice {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Scope,
        [string]$Tenant = 'organizations'
    )
    $base = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0"
    $dc = Invoke-RestMethod -Method Post -Uri "$base/devicecode" -Body @{ client_id = $ClientId; scope = $Scope }
    Write-Host ''
    Write-Host "  [$Name] $($dc.message)" -ForegroundColor Cyan
    try { Set-Clipboard -Value $dc.user_code; Write-Host '  (code copied to clipboard)' -ForegroundColor DarkGray } catch { }
    try { Start-Process $dc.verification_uri } catch { }

    $deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
    $interval = [int]$dc.interval; if ($interval -lt 1) { $interval = 5 }
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $t = Invoke-RestMethod -Method Post -Uri "$base/token" -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $dc.device_code
            }
            Save-KitToken -Name $Name -Response $t -ClientId $ClientId -Tenant $Tenant -Scope $Scope
            Write-Host "  [$Name] signed in as $($script:Tokens[$Name].user)" -ForegroundColor Green
            return
        } catch {
            $err = $null
            try { $err = $_.ErrorDetails.Message | ConvertFrom-Json } catch { }
            if ($err -and $err.error -eq 'authorization_pending') { continue }
            if ($err -and $err.error -eq 'slow_down') { $interval += 5; continue }
            $why = if ($err) { $err.error_description } else { $_.Exception.Message }
            throw "Sign-in failed: $why"
        }
    }
    throw 'Sign-in timed out.'
}

function Get-KitToken {
    param([Parameter(Mandatory)][string]$Name)
    $t = $script:Tokens[$Name]
    if (-not $t) { throw "Not signed in to '$Name'." }
    if ($t.expires -lt (Get-Date).AddMinutes(5)) {
        if (-not $t.refresh) { throw "Session for '$Name' expired. Restart the tool to sign in again." }
        $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($t.tenant)/oauth2/v2.0/token" -Body @{
            grant_type    = 'refresh_token'
            client_id     = $t.clientId
            refresh_token = $t.refresh
            scope         = $t.scope
        }
        Save-KitToken -Name $Name -Response $r -ClientId $t.clientId -Tenant $t.tenant -Scope $t.scope
        $t = $script:Tokens[$Name]
    }
    $t
}

function Test-KitSignedIn { param([string]$Name) [bool]$script:Tokens[$Name] }
