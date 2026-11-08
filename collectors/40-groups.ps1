@{
    Id = 'groups'; Title = 'Groups'; Icon = '👥'; Order = 40; Target = 'graph'
    Run = {
        $g = @(Invoke-Graph '/groups?$select=id,displayName,groupTypes,securityEnabled,mailEnabled,membershipRule,createdDateTime,onPremisesSyncEnabled,visibility&$top=999' -All)
        $kind = { param($x)
            if ($x.groupTypes -contains 'Unified') { 'Microsoft 365' }
            elseif ($x.securityEnabled -and $x.mailEnabled) { 'Mail-enabled security' }
            elseif ($x.securityEnabled) { 'Security' } elseif ($x.mailEnabled) { 'Distribution' } else { 'Other' } }
        $rows = foreach ($x in $g) { [pscustomobject]@{ g = $x; kind = (& $kind $x); dynamic = ($x.groupTypes -contains 'DynamicMembership') } }
        $public = @($rows | Where-Object { $_.kind -eq 'Microsoft 365' -and $_.g.visibility -eq 'Public' })
        $findings = @()
        if ($public.Count) { $findings += New-KitFinding low "$($public.Count) Microsoft 365 groups are Public (anyone in the tenant can join)." }
        @{
            summary = @(
                @{ label = 'Groups'; value = $g.Count }
                @{ label = 'Microsoft 365'; value = @($rows | Where-Object { $_.kind -eq 'Microsoft 365' }).Count }
                @{ label = 'Security'; value = @($rows | Where-Object { $_.kind -like '*ecurity' }).Count }
                @{ label = 'Dynamic'; value = @($rows | Where-Object dynamic).Count }
            )
            charts = @(
                @{ title = 'Group types'; type = 'donut'; items = (New-KitItems $rows 'kind') }
                @{ title = 'Membership'; type = 'donut'; items = @(@{ label = 'Assigned'; value = @($rows | Where-Object { -not $_.dynamic }).Count }, @{ label = 'Dynamic'; value = @($rows | Where-Object dynamic).Count }) }
                @{ title = 'Created per year'; type = 'bar'; items = @(New-KitItems $rows { (ConvertTo-KitDate $_.g.createdDateTime).Year } | Sort-Object { $_.label }) }
            )
            tables = @(@{ title = 'Groups'; columns = @('name', 'type', 'dynamic', 'visibility', 'synced', 'created'); rows = @($rows | ForEach-Object {
                        [ordered]@{ name = $_.g.displayName; type = $_.kind; dynamic = [string]$_.dynamic; visibility = $_.g.visibility; synced = [string][bool]$_.g.onPremisesSyncEnabled; created = (Format-KitDate $_.g.createdDateTime) } }) })
            findings = $findings
        }
    }
}
