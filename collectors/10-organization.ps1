@{
    Id = 'org'; Title = 'Tenant'; Icon = '🏢'; Order = 10; Target = 'graph'
    Run = {
        $org = @(Invoke-Graph '/organization')[0].value | Select-Object -First 1
        $domains = @(Invoke-Graph '/domains' -All)
        $verified = @($domains | Where-Object isVerified)
        $primary = ($domains | Where-Object isDefault | Select-Object -First 1).id
        $synced = [bool]$org.onPremisesSyncEnabled
        $findings = @()
        if (@($domains | Where-Object { -not $_.isVerified }).Count) { $findings += New-KitFinding low "$(@($domains | Where-Object { -not $_.isVerified }).Count) domain(s) are not verified." }
        @{
            summary = @(
                @{ label = 'Tenant'; value = $org.displayName; text = $true }
                @{ label = 'Primary domain'; value = $primary; text = $true }
                @{ label = 'Domains'; value = $domains.Count; hint = "$($verified.Count) verified" }
                @{ label = 'Hybrid sync'; value = $(if ($synced) { 'On' } else { 'Cloud only' }); text = $true }
                @{ label = 'Created'; value = (Format-KitDate $org.createdDateTime); text = $true }
                @{ label = 'Country'; value = $org.countryLetterCode; text = $true }
            )
            charts = @(@{ title = 'Domains by authentication'; type = 'donut'; items = (New-KitItems $domains 'authenticationType') })
            tables = @(@{ title = 'Domains'; columns = @('name', 'default', 'verified', 'type', 'services'); rows = @($domains | ForEach-Object {
                        [ordered]@{ name = $_.id; default = [string][bool]$_.isDefault; verified = [string][bool]$_.isVerified; type = $_.authenticationType; services = ($_.supportedServices -join ', ') } }) })
            findings = $findings
        }
    }
}
