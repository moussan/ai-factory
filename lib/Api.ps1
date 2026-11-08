# REST helpers for Microsoft Graph and Azure Resource Manager (read-only: GET only).

function Invoke-KitRequest {
    param([string]$Target, [string]$Uri, [switch]$Raw, [hashtable]$ExtraHeaders)
    $tok = Get-KitToken -Name $Target
    $Uri = $Uri.Replace(' ', '%20')
    $headers = @{ Authorization = "Bearer $($tok.access)" }
    if ($ExtraHeaders) { foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] } }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            if ($Raw) {
                $c = (Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -Method Get).Content
                if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }   # reports come back as octet-stream
                return $c
            }
            return Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
        } catch {
            $code = 0
            if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { } }
            if (($code -eq 429 -or $code -eq 503 -or $code -eq 504) -and $i -lt 4) {
                Start-Sleep -Seconds ([math]::Pow(2, $i + 1)); continue
            }
            $detail = $_.Exception.Message
            try { $detail = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch { }
            throw "HTTP $code - $detail"
        }
    }
}

function Invoke-Graph {
    param([Parameter(Mandatory)][string]$Path, [switch]$All, [switch]$Beta, [switch]$Raw, [switch]$Eventual, [int]$Max = 0)
    $base = if ($Beta) { 'https://graph.microsoft.com/beta' } else { 'https://graph.microsoft.com/v1.0' }
    $uri = if ($Path -match '^https://') { $Path } else { $base + $Path }
    $h = @{}; if ($Eventual) { $h['ConsistencyLevel'] = 'eventual' }
    if ($Raw) { return Invoke-KitRequest -Target graph -Uri $uri -Raw -ExtraHeaders $h }
    if (-not $All) { return Invoke-KitRequest -Target graph -Uri $uri -ExtraHeaders $h }
    $items = New-Object System.Collections.ArrayList
    while ($uri) {
        $r = Invoke-KitRequest -Target graph -Uri $uri -ExtraHeaders $h
        if ($r.value) { [void]$items.AddRange(@($r.value)) }
        $uri = $r.'@odata.nextLink'
        if ($Max -gt 0 -and $items.Count -ge $Max) { break }
    }
    $items.ToArray()
}

function Invoke-Arm {
    param([Parameter(Mandatory)][string]$Path, [switch]$All)
    $uri = if ($Path -match '^https://') { $Path } else { 'https://management.azure.com' + $Path }
    if (-not $All) { return Invoke-KitRequest -Target arm -Uri $uri }
    $items = New-Object System.Collections.ArrayList
    while ($uri) {
        $r = Invoke-KitRequest -Target arm -Uri $uri
        if ($r.value) { [void]$items.AddRange(@($r.value)) }
        $uri = $r.nextLink
    }
    $items.ToArray()
}

# ---- small helpers collectors use -------------------------------------------------

function ConvertTo-KitDate { param($Value) if ($Value) { try { [datetime]$Value } catch { $null } } }

function Format-KitDate { param($Value) $d = ConvertTo-KitDate $Value; if ($d) { $d.ToUniversalTime().ToString('yyyy-MM-dd') } else { '' } }

# Group objects by a property/scriptblock and return chart items [{label,value}] sorted by size.
function New-KitItems {
    param($InputObject, $By, [int]$Top = 0)
    $g = @($InputObject | Group-Object -Property $By | Sort-Object Count -Descending)
    if ($Top -gt 0) { $g = @($g | Select-Object -First $Top) }
    @($g | ForEach-Object {
            $name = if ([string]::IsNullOrWhiteSpace([string]$_.Name)) { '(none)' } else { [string]$_.Name }
            @{ label = $name; value = $_.Count }
        })
}

function New-KitFinding { param([ValidateSet('high', 'medium', 'low', 'info', 'good')][string]$Severity, [string]$Text) @{ severity = $Severity; text = $Text } }
