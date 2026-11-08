@{
    Id = 'intune'; Title = 'Intune devices'; Icon = '📱'; Order = 95; Target = 'graph'
    Run = {
        $d = @(Invoke-Graph '/deviceManagement/managedDevices?$select=deviceName,operatingSystem,osVersion,complianceState,ownerType,lastSyncDateTime,userPrincipalName,model,manufacturer&$top=999' -All)
        $now = Get-Date
        $stale = @($d | Where-Object { $x = ConvertTo-KitDate $_.lastSyncDateTime; $x -and ($now - $x).TotalDays -gt 30 })
        $nc = @($d | Where-Object complianceState -eq 'noncompliant')
        $findings = @()
        if ($nc.Count) { $findings += New-KitFinding medium "$($nc.Count) Intune devices are non-compliant." }
        if ($stale.Count) { $findings += New-KitFinding low "$($stale.Count) Intune devices haven't synced in 30+ days." }
        @{
            summary = @(
                @{ label = 'Managed devices'; value = $d.Count }
                @{ label = 'Compliant'; value = @($d | Where-Object complianceState -eq 'compliant').Count; tone = 'good' }
                @{ label = 'Non-compliant'; value = $nc.Count; tone = $(if ($nc.Count) { 'bad' } else { 'good' }) }
                @{ label = 'Not synced 30d+'; value = $stale.Count }
            )
            charts = @(
                @{ title = 'Compliance'; type = 'donut'; items = (New-KitItems $d 'complianceState') }
                @{ title = 'Operating system'; type = 'donut'; items = (New-KitItems $d 'operatingSystem') }
                @{ title = 'Ownership'; type = 'donut'; items = (New-KitItems $d 'ownerType') }
                @{ title = 'Top models'; type = 'bar'; items = (New-KitItems $d { "$($_.manufacturer) $($_.model)" } -Top 10) }
            )
            tables = @(@{ title = 'Managed devices'; columns = @('device', 'user', 'os', 'version', 'compliance', 'owner', 'lastSync'); rows = @($d | ForEach-Object {
                        [ordered]@{ device = $_.deviceName; user = $_.userPrincipalName; os = $_.operatingSystem; version = $_.osVersion; compliance = $_.complianceState; owner = $_.ownerType; lastSync = (Format-KitDate $_.lastSyncDateTime) } }) })
            findings = $findings
        }
    }
}
