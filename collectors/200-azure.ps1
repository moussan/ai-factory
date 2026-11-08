@{
    Id = 'azure'; Title = 'Azure resources'; Icon = '☁️'; Order = 200; Target = 'arm'
    Run = {
        $subs = @(Invoke-Arm '/subscriptions?api-version=2022-12-01' -All)
        $res = @()
        foreach ($s in $subs) {
            foreach ($r in @(Invoke-Arm "/subscriptions/$($s.subscriptionId)/resources?api-version=2021-04-01&`$top=1000" -All)) {
                $rg = if ($r.id -match '/resourceGroups/([^/]+)/') { $Matches[1] } else { '' }
                $res += [pscustomobject]@{ name = $r.name; type = $r.type; location = $r.location; rg = $rg; sub = $s.displayName; kind = $r.kind }
            }
        }
        $findings = @()
        $disabledSubs = @($subs | Where-Object { $_.state -ne 'Enabled' })
        if ($disabledSubs.Count) { $findings += New-KitFinding low "$($disabledSubs.Count) subscription(s) are not in Enabled state." }
        $score = $null
        try { $score = @(Invoke-Arm "/subscriptions/$($subs[0].subscriptionId)/providers/Microsoft.Security/secureScores?api-version=2020-01-01" -All)[0] } catch { }
        $summary = @(
            @{ label = 'Subscriptions'; value = $subs.Count }
            @{ label = 'Resources'; value = $res.Count }
            @{ label = 'Resource groups'; value = @($res | Select-Object -ExpandProperty rg -Unique).Count }
            @{ label = 'Regions'; value = @($res | Select-Object -ExpandProperty location -Unique).Count }
        )
        if ($score) { $summary += @{ label = 'Defender score'; value = "$([math]::Round($score.properties.score.percentage * 100))%"; text = $true } }
        @{
            summary = $summary
            charts = @(
                @{ title = 'Resources by type'; type = 'bar'; items = (New-KitItems $res 'type' -Top 12) }
                @{ title = 'Resources by region'; type = 'donut'; items = (New-KitItems $res 'location' -Top 8) }
                @{ title = 'Resources by subscription'; type = 'bar'; items = (New-KitItems $res 'sub' -Top 10) }
                @{ title = 'Largest resource groups'; type = 'bar'; items = (New-KitItems $res 'rg' -Top 10) }
            )
            tables = @(
                @{ title = 'Subscriptions'; columns = @('name', 'id', 'state'); rows = @($subs | ForEach-Object { [ordered]@{ name = $_.displayName; id = $_.subscriptionId; state = $_.state } }) }
                @{ title = 'Resources'; columns = @('name', 'type', 'location', 'resourceGroup', 'subscription'); rows = @($res | ForEach-Object { [ordered]@{ name = $_.name; type = $_.type; location = $_.location; resourceGroup = $_.rg; subscription = $_.sub } }) }
            )
            findings = $findings
        }
    }
}
