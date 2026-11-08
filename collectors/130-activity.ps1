@{
    Id = 'activity'; Title = 'M365 activity'; Icon = '⚡'; Order = 130; Target = 'graph'
    Run = {
        $csv = (Invoke-Graph "/reports/getOffice365ActiveUserCounts(period='D30')" -Raw).TrimStart([char]0xFEFF)
        $rows = @($csv | ConvertFrom-Csv | Sort-Object 'Report Date')
        if (-not $rows.Count) { throw 'No activity report data returned.' }
        $last = $rows[-1]
        $svc = 'Exchange', 'OneDrive', 'SharePoint', 'Teams', 'Yammer'
        @{
            summary = @($svc | ForEach-Object { @{ label = "$_ active (latest)"; value = [int]$last.$_ } })
            charts = @(
                @{ title = 'Active users per service (latest day)'; type = 'bar'; items = @($svc | ForEach-Object { @{ label = $_; value = [int]$last.$_ } }) }
                @{ title = 'Teams active users (30 days)'; type = 'line'; items = @($rows | ForEach-Object { @{ label = $_.'Report Date'; value = [int]$_.Teams } }) }
                @{ title = 'Exchange active users (30 days)'; type = 'line'; items = @($rows | ForEach-Object { @{ label = $_.'Report Date'; value = [int]$_.Exchange } }) }
                @{ title = 'SharePoint active users (30 days)'; type = 'line'; items = @($rows | ForEach-Object { @{ label = $_.'Report Date'; value = [int]$_.SharePoint } }) }
            )
        }
    }
}
