@{
    Id = 'security'; Title = 'Security posture'; Icon = '🔒'; Order = 100; Target = 'graph'
    Run = {
        $score = @(Invoke-Graph '/security/secureScores?$top=1')[0].value | Select-Object -First 1
        $risky = @()
        try { $risky = @(Invoke-Graph '/identityProtection/riskyUsers?$top=500' -All) } catch { $riskErr = $_.Exception.Message }
        $atRisk = @($risky | Where-Object riskState -eq 'atRisk')
        $findings = @()
        $pct = if ($score -and $score.maxScore) { [math]::Round(100 * $score.currentScore / $score.maxScore) } else { 0 }
        if ($score) {
            $sev = if ($pct -lt 40) { 'high' } elseif ($pct -lt 65) { 'medium' } else { 'good' }
            $findings += New-KitFinding $sev "Microsoft Secure Score is $pct% ($([math]::Round($score.currentScore,1)) / $([math]::Round($score.maxScore,1)))."
        }
        $hi = @($atRisk | Where-Object riskLevel -eq 'high')
        if ($hi.Count) { $findings += New-KitFinding high "$($hi.Count) user(s) are at HIGH identity risk." }
        elseif ($riskErr) { $findings += New-KitFinding info 'Risky users unavailable (needs Entra ID P2 + IdentityRiskyUser.Read.All).' }
        $todo = @($score.controlScores | Where-Object { $_.score -eq 0 })
        @{
            summary = @(
                @{ label = 'Secure Score'; value = "$pct%"; text = $true; hint = "$([math]::Round($score.currentScore,1)) of $([math]::Round($score.maxScore,1))"; tone = $(if ($pct -ge 65) { 'good' } elseif ($pct -ge 40) { 'warn' } else { 'bad' }) }
                @{ label = 'Risky users'; value = $atRisk.Count; tone = $(if ($atRisk.Count) { 'bad' } else { 'good' }) }
                @{ label = 'Controls at 0'; value = $todo.Count }
            )
            charts = @(
                @{ title = 'Score by category'; type = 'bar'; items = @($score.controlScores | Group-Object controlCategory | ForEach-Object { @{ label = $_.Name; value = [math]::Round(($_.Group | Measure-Object score -Sum).Sum, 1) } }) }
                @{ title = 'Users at risk by level'; type = 'donut'; items = (New-KitItems $atRisk 'riskLevel') }
            )
            tables = @(
                @{ title = 'Secure Score controls with no points'; columns = @('control', 'category', 'description'); rows = @($todo | ForEach-Object { [ordered]@{ control = $_.controlName; category = $_.controlCategory; description = $_.description } }) }
                @{ title = 'Users at risk'; columns = @('user', 'upn', 'level', 'state', 'updated'); rows = @($atRisk | ForEach-Object { [ordered]@{ user = $_.userDisplayName; upn = $_.userPrincipalName; level = $_.riskLevel; state = $_.riskState; updated = (Format-KitDate $_.riskLastUpdatedDateTime) } }) }
            )
            findings = $findings
        }
    }
}
