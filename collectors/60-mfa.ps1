@{
    Id = 'mfa'; Title = 'MFA & auth methods'; Icon = '🔐'; Order = 60; Target = 'graph'
    Run = {
        $d = @(Invoke-Graph '/reports/authenticationMethods/userRegistrationDetails' -All)
        $reg = @($d | Where-Object isMfaRegistered)
        $unreg = @($d | Where-Object { -not $_.isMfaRegistered })
        $admins = @($d | Where-Object isAdmin)
        $adminNo = @($admins | Where-Object { -not $_.isMfaRegistered })
        $pwless = @($d | Where-Object isPasswordlessCapable)
        $methods = foreach ($x in $d) { foreach ($m in @($x.methodsRegistered)) { [pscustomobject]@{ m = $m } } }
        $findings = @()
        if ($adminNo.Count) { $findings += New-KitFinding high "$($adminNo.Count) admin account(s) have NOT registered MFA." }
        elseif ($admins.Count) { $findings += New-KitFinding good 'All admin accounts have MFA registered.' }
        $pct = if ($d.Count) { [math]::Round(100 * $reg.Count / $d.Count) } else { 0 }
        if ($pct -lt 90) { $findings += New-KitFinding medium "Only $pct% of users have registered MFA." }
        @{
            summary = @(
                @{ label = 'MFA registered'; value = "$pct%"; text = $true; hint = "$($reg.Count) of $($d.Count)"; tone = $(if ($pct -ge 90) { 'good' } else { 'warn' }) }
                @{ label = 'Without MFA'; value = $unreg.Count; tone = $(if ($unreg.Count) { 'warn' } else { 'good' }) }
                @{ label = 'Admins without MFA'; value = $adminNo.Count; tone = $(if ($adminNo.Count) { 'bad' } else { 'good' }) }
                @{ label = 'Passwordless-capable'; value = $pwless.Count }
            )
            charts = @(
                @{ title = 'MFA registration'; type = 'donut'; items = @(@{ label = 'Registered'; value = $reg.Count }, @{ label = 'Not registered'; value = $unreg.Count }) }
                @{ title = 'Methods registered'; type = 'bar'; items = (New-KitItems $methods 'm' -Top 10) }
                @{ title = 'Default MFA method'; type = 'donut'; items = (New-KitItems @($d | Where-Object defaultMfaMethod -ne 'none') 'defaultMfaMethod') }
            )
            tables = @(@{ title = 'Users without MFA'; columns = @('name', 'upn', 'admin', 'methods'); rows = @($unreg | ForEach-Object {
                        [ordered]@{ name = $_.userDisplayName; upn = $_.userPrincipalName; admin = [string][bool]$_.isAdmin; methods = (@($_.methodsRegistered) -join ', ') } }) })
            findings = $findings
        }
    }
}
