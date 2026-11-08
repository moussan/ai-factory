@{
    Id = 'licenses'; Title = 'Licenses'; Icon = '🎫'; Order = 30; Target = 'graph'
    Run = {
        $names = @{
            SPE_E3 = 'Microsoft 365 E3'; SPE_E5 = 'Microsoft 365 E5'; ENTERPRISEPACK = 'Office 365 E3'; ENTERPRISEPREMIUM = 'Office 365 E5'
            STANDARDPACK = 'Office 365 E1'; O365_BUSINESS_PREMIUM = 'Microsoft 365 Business Standard'; SPB = 'Microsoft 365 Business Premium'
            O365_BUSINESS_ESSENTIALS = 'Microsoft 365 Business Basic'; EMS = 'EMS E3'; EMSPREMIUM = 'EMS E5'; AAD_PREMIUM = 'Entra ID P1'
            AAD_PREMIUM_P2 = 'Entra ID P2'; POWER_BI_PRO = 'Power BI Pro'; FLOW_FREE = 'Power Automate Free'; TEAMS_EXPLORATORY = 'Teams Exploratory'
            EXCHANGESTANDARD = 'Exchange Online (Plan 1)'; EXCHANGEENTERPRISE = 'Exchange Online (Plan 2)'; WINDOWS_STORE = 'Windows Store'
            Microsoft_365_Copilot = 'Microsoft 365 Copilot'; VISIOCLIENT = 'Visio Plan 2'; PROJECTPREMIUM = 'Project Plan 5'
        }
        $skus = @(Invoke-Graph '/subscribedSkus' -All | Where-Object { $_.appliesTo -eq 'User' })
        $rows = foreach ($s in $skus) {
            $total = [int]$s.prepaidUnits.enabled
            $name = if ($names[$s.skuPartNumber]) { $names[$s.skuPartNumber] } else { $s.skuPartNumber }
            [pscustomobject]@{ name = $name; part = $s.skuPartNumber; total = $total; used = [int]$s.consumedUnits; free = $total - [int]$s.consumedUnits
                suspended = [int]$s.prepaidUnits.suspended + [int]$s.prepaidUnits.warning; status = $s.capabilityStatus }
        }
        $paid = @($rows | Where-Object { $_.total -lt 10000 -and $_.total -gt 0 })
        $findings = @()
        foreach ($r in ($paid | Where-Object { $_.free -ge 5 -and $_.total -gt 0 -and ($_.free / $_.total) -ge 0.2 } | Select-Object -First 5)) {
            $findings += New-KitFinding medium "$($r.name): $($r.free) of $($r.total) licenses unassigned."
        }
        foreach ($r in ($rows | Where-Object { $_.free -le 0 -and $_.total -gt 0 -and $_.total -lt 10000 } | Select-Object -First 5)) {
            $findings += New-KitFinding low "$($r.name): no licenses left ($($r.used)/$($r.total) used)."
        }
        @{
            summary = @(
                @{ label = 'License SKUs'; value = $rows.Count }
                @{ label = 'Assigned seats'; value = [int](($paid | Measure-Object used -Sum).Sum) }
                @{ label = 'Unassigned seats'; value = [int](($paid | Measure-Object free -Sum).Sum); tone = 'warn' }
            )
            charts = @(
                @{ title = 'Assigned seats by SKU'; type = 'bar'; items = @($paid | Sort-Object used -Descending | Select-Object -First 10 | ForEach-Object { @{ label = $_.name; value = $_.used } }) }
                @{ title = 'Unassigned seats by SKU'; type = 'bar'; items = @($paid | Where-Object free -gt 0 | Sort-Object free -Descending | Select-Object -First 10 | ForEach-Object { @{ label = $_.name; value = $_.free } }) }
            )
            tables = @(@{ title = 'Subscriptions'; columns = @('name', 'part', 'total', 'used', 'free', 'suspended', 'status'); rows = @($rows | ForEach-Object { [ordered]@{ name = $_.name; part = $_.part; total = $_.total; used = $_.used; free = $_.free; suspended = $_.suspended; status = $_.status } }) })
            findings = $findings
        }
    }
}
