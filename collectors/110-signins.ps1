@{
    Id = 'signins'; Title = 'Sign-ins (24h)'; Icon = '📈'; Order = 110; Target = 'graph'
    Run = {
        $since = (Get-Date).ToUniversalTime().AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $s = @(Invoke-Graph "/auditLogs/signIns?`$filter=createdDateTime ge $since&`$top=500" -All -Max 3000)
        $ok = @($s | Where-Object { $_.status.errorCode -eq 0 }); $bad = @($s | Where-Object { $_.status.errorCode -ne 0 })
        $hours = @($s | Group-Object { (ConvertTo-KitDate $_.createdDateTime).ToUniversalTime().ToString('HH:00') } | Sort-Object Name | ForEach-Object { @{ label = $_.Name; value = $_.Count } })
        $findings = @()
        $rate = if ($s.Count) { [math]::Round(100 * $bad.Count / $s.Count) } else { 0 }
        if ($rate -gt 25) { $findings += New-KitFinding medium "$rate% of the last 24h sign-ins failed - possible spray/brute-force activity." }
        $risky = @($s | Where-Object { $_.riskLevelDuringSignIn -in 'high', 'medium' })
        if ($risky.Count) { $findings += New-KitFinding medium "$($risky.Count) sign-ins were flagged medium/high risk." }
        $legacy = @($s | Where-Object { $_.clientAppUsed -in 'Exchange ActiveSync', 'IMAP4', 'POP3', 'SMTP', 'Other clients' })
        if ($legacy.Count) { $findings += New-KitFinding medium "$($legacy.Count) sign-ins used legacy authentication protocols." }
        @{
            summary = @(
                @{ label = 'Sign-ins (24h)'; value = $s.Count; hint = $(if ($s.Count -ge 3000) { 'first 3000 sampled' } else { '' }) }
                @{ label = 'Successful'; value = $ok.Count; tone = 'good' }
                @{ label = 'Failed'; value = $bad.Count; tone = $(if ($rate -gt 25) { 'bad' } else { 'warn' }) }
                @{ label = 'Unique users'; value = @($s | Select-Object -ExpandProperty userPrincipalName -Unique).Count }
            )
            charts = @(
                @{ title = 'Sign-ins per hour (UTC)'; type = 'line'; items = $hours }
                @{ title = 'Outcome'; type = 'donut'; items = @(@{ label = 'Success'; value = $ok.Count }, @{ label = 'Failure'; value = $bad.Count }) }
                @{ title = 'Top applications'; type = 'bar'; items = (New-KitItems $s 'appDisplayName' -Top 10) }
                @{ title = 'Countries'; type = 'bar'; items = (New-KitItems $s { $_.location.countryOrRegion } -Top 10) }
                @{ title = 'Top failure reasons'; type = 'bar'; items = (New-KitItems $bad { $_.status.failureReason } -Top 8) }
                @{ title = 'Client apps'; type = 'donut'; items = (New-KitItems $s 'clientAppUsed') }
            )
            tables = @(@{ title = 'Failed sign-ins'; columns = @('time', 'user', 'app', 'country', 'ip', 'reason'); rows = @($bad | Select-Object -First 500 | ForEach-Object {
                        [ordered]@{ time = $_.createdDateTime; user = $_.userPrincipalName; app = $_.appDisplayName; country = $_.location.countryOrRegion; ip = $_.ipAddress; reason = $_.status.failureReason } }) })
            findings = $findings
        }
    }
}
