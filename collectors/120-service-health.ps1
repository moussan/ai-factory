@{
    Id = 'health'; Title = 'Service health'; Icon = '❤️'; Order = 120; Target = 'graph'
    Run = {
        $h = @(Invoke-Graph '/admin/serviceAnnouncement/healthOverviews' -All)
        $bad = @($h | Where-Object { $_.status -ne 'serviceOperational' })
        $findings = @()
        foreach ($b in $bad) { $findings += New-KitFinding medium "$($b.service): $($b.status)" }
        if (-not $bad.Count) { $findings += New-KitFinding good 'All Microsoft 365 services report operational.' }
        @{
            summary = @(@{ label = 'Services'; value = $h.Count }, @{ label = 'Operational'; value = $h.Count - $bad.Count; tone = 'good' }, @{ label = 'Degraded / issues'; value = $bad.Count; tone = $(if ($bad.Count) { 'warn' } else { 'good' }) })
            charts = @(@{ title = 'Service status'; type = 'donut'; items = (New-KitItems $h 'status') })
            tables = @(@{ title = 'Services'; columns = @('service', 'status'); rows = @($h | Sort-Object status, service | ForEach-Object { [ordered]@{ service = $_.service; status = $_.status } }) })
            findings = $findings
        }
    }
}
