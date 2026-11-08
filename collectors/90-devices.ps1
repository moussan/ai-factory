@{
    Id = 'devices'; Title = 'Entra devices'; Icon = '💻'; Order = 90; Target = 'graph'
    Run = {
        $d = @(Invoke-Graph '/devices?$select=id,displayName,operatingSystem,operatingSystemVersion,isCompliant,isManaged,trustType,approximateLastSignInDateTime,accountEnabled&$top=999' -All)
        $now = Get-Date
        $stale = @($d | Where-Object { $x = ConvertTo-KitDate $_.approximateLastSignInDateTime; $x -and ($now - $x).TotalDays -gt 90 })
        $findings = @()
        if ($stale.Count) { $findings += New-KitFinding low "$($stale.Count) devices haven't signed in for 90+ days - clean up stale objects." }
        $nc = @($d | Where-Object { $_.isManaged -and $_.isCompliant -eq $false })
        if ($nc.Count) { $findings += New-KitFinding medium "$($nc.Count) managed devices are non-compliant." }
        @{
            summary = @(
                @{ label = 'Devices'; value = $d.Count }
                @{ label = 'Managed'; value = @($d | Where-Object isManaged).Count }
                @{ label = 'Compliant'; value = @($d | Where-Object isCompliant).Count }
                @{ label = 'Stale (90d+)'; value = $stale.Count; tone = $(if ($stale.Count) { 'warn' } else { 'good' }) }
            )
            charts = @(
                @{ title = 'Operating system'; type = 'donut'; items = (New-KitItems $d 'operatingSystem') }
                @{ title = 'Join type'; type = 'donut'; items = (New-KitItems $d 'trustType') }
                @{ title = 'Compliance'; type = 'donut'; items = (New-KitItems @($d | Where-Object isManaged) { if ($_.isCompliant) { 'Compliant' } else { 'Non-compliant' } }) }
            )
            tables = @(@{ title = 'Devices'; columns = @('name', 'os', 'version', 'join', 'managed', 'compliant', 'lastSignIn'); rows = @($d | ForEach-Object {
                        [ordered]@{ name = $_.displayName; os = $_.operatingSystem; version = $_.operatingSystemVersion; join = $_.trustType; managed = [string][bool]$_.isManaged; compliant = [string][bool]$_.isCompliant; lastSignIn = (Format-KitDate $_.approximateLastSignInDateTime) } }) })
            findings = $findings
        }
    }
}
