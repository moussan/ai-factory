@{
    Id = 'ca'; Title = 'Conditional Access'; Icon = '🚦'; Order = 70; Target = 'graph'
    Run = {
        $p = @(Invoke-Graph '/identity/conditionalAccess/policies' -All)
        $on = @($p | Where-Object state -eq 'enabled')
        $report = @($p | Where-Object state -eq 'enabledForReportingButNotEnforced')
        $mfa = @($on | Where-Object { @($_.grantControls.builtInControls) -contains 'mfa' -or $_.grantControls.authenticationStrength })
        $block = @($on | Where-Object { @($_.grantControls.builtInControls) -contains 'block' })
        $findings = @()
        if (-not $on.Count) { $findings += New-KitFinding high 'No Conditional Access policy is enforced.' }
        elseif (-not $mfa.Count) { $findings += New-KitFinding high 'No enforced policy requires MFA.' }
        else { $findings += New-KitFinding good "$($mfa.Count) enforced policy/policies require MFA." }
        if ($report.Count) { $findings += New-KitFinding low "$($report.Count) policy/policies are in report-only mode." }
        $legacy = @($on | Where-Object { @($_.conditions.clientAppTypes) -contains 'exchangeActiveSync' -and @($_.grantControls.builtInControls) -contains 'block' })
        if (-not $legacy.Count) { $findings += New-KitFinding medium 'No enforced policy blocks legacy authentication.' }
        @{
            summary = @(
                @{ label = 'Policies'; value = $p.Count }
                @{ label = 'Enforced'; value = $on.Count; tone = $(if ($on.Count) { 'good' } else { 'bad' }) }
                @{ label = 'Report-only'; value = $report.Count }
                @{ label = 'Require MFA'; value = $mfa.Count }
                @{ label = 'Block policies'; value = $block.Count }
            )
            charts = @(@{ title = 'Policy state'; type = 'donut'; items = (New-KitItems $p { switch ($_.state) { 'enabled' { 'Enforced' } 'disabled' { 'Disabled' } default { 'Report-only' } } }) })
            tables = @(@{ title = 'Policies'; columns = @('name', 'state', 'grant', 'created', 'modified'); rows = @($p | ForEach-Object {
                        [ordered]@{ name = $_.displayName; state = $_.state; grant = (@($_.grantControls.builtInControls) -join ', '); created = (Format-KitDate $_.createdDateTime); modified = (Format-KitDate $_.modifiedDateTime) } }) })
            findings = $findings
        }
    }
}
