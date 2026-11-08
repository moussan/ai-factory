@{
    Id = 'users'; Title = 'Users'; Icon = '👤'; Order = 20; Target = 'graph'
    Run = {
        $sel = 'id,displayName,userPrincipalName,accountEnabled,userType,createdDateTime,assignedLicenses,onPremisesSyncEnabled'
        $hasSignIn = $true
        try { $u = @(Invoke-Graph "/users?`$select=$sel,signInActivity&`$top=999" -All) }
        catch { $hasSignIn = $false; $u = @(Invoke-Graph "/users?`$select=$sel&`$top=999" -All) }

        $now = Get-Date
        $rows = foreach ($x in $u) {
            $last = $null; if ($hasSignIn -and $x.signInActivity) { $last = ConvertTo-KitDate $x.signInActivity.lastSignInDateTime }
            [pscustomobject]@{
                u = $x; last = $last
                days = $(if ($last) { [int]($now - $last).TotalDays } else { $null })
            }
        }
        $members = @($rows | Where-Object { $_.u.userType -eq 'Member' })
        $guests = @($rows | Where-Object { $_.u.userType -eq 'Guest' })
        $disabled = @($rows | Where-Object { $_.u.accountEnabled -eq $false })
        $licensed = @($rows | Where-Object { @($_.u.assignedLicenses).Count -gt 0 })
        $stale = @($members | Where-Object { $_.u.accountEnabled -and $_.last -and $_.days -gt 90 })
        $never = @($members | Where-Object { $_.u.accountEnabled -and $hasSignIn -and -not $_.last })
        $findings = @()
        if ($stale.Count) { $findings += New-KitFinding medium "$($stale.Count) enabled member accounts haven't signed in for 90+ days." }
        if ($never.Count) { $findings += New-KitFinding low "$($never.Count) enabled member accounts have never signed in." }
        $dl = @($disabled | Where-Object { @($_.u.assignedLicenses).Count -gt 0 })
        if ($dl.Count) { $findings += New-KitFinding medium "$($dl.Count) disabled accounts still hold licenses (reclaimable spend)." }
        if ($guests.Count -gt $members.Count * 0.5 -and $guests.Count -gt 10) { $findings += New-KitFinding low "Guests ($($guests.Count)) outnumber half of members - review external access." }
        if (-not $hasSignIn) { $findings += New-KitFinding info 'Sign-in activity unavailable (needs Entra ID P1 + AuditLog.Read.All).' }

        $buckets = @(
            @{ label = '< 7 days'; value = @($members | Where-Object { $_.last -and $_.days -lt 7 }).Count }
            @{ label = '7-30 days'; value = @($members | Where-Object { $_.last -and $_.days -ge 7 -and $_.days -lt 30 }).Count }
            @{ label = '30-90 days'; value = @($members | Where-Object { $_.last -and $_.days -ge 30 -and $_.days -le 90 }).Count }
            @{ label = '90+ days'; value = $stale.Count }
            @{ label = 'Never'; value = $never.Count }
        )
        @{
            summary = @(
                @{ label = 'Total users'; value = $u.Count }
                @{ label = 'Members'; value = $members.Count }
                @{ label = 'Guests'; value = $guests.Count }
                @{ label = 'Disabled'; value = $disabled.Count }
                @{ label = 'Licensed'; value = $licensed.Count }
                @{ label = 'Stale (90d+)'; value = $stale.Count; tone = $(if ($stale.Count) { 'warn' } else { 'good' }) }
            )
            charts = @(
                @{ title = 'Member vs guest'; type = 'donut'; items = (New-KitItems $rows { $_.u.userType }) }
                @{ title = 'Account status'; type = 'donut'; items = @(@{ label = 'Enabled'; value = $u.Count - $disabled.Count }, @{ label = 'Disabled'; value = $disabled.Count }) }
                @{ title = 'Source'; type = 'donut'; items = @(@{ label = 'Cloud'; value = @($u | Where-Object { -not $_.onPremisesSyncEnabled }).Count }, @{ label = 'Synced from on-prem'; value = @($u | Where-Object { $_.onPremisesSyncEnabled }).Count }) }
                @{ title = 'Last sign-in (members)'; type = 'bar'; items = $buckets }
            )
            tables = @(@{ title = 'All users'; columns = @('name', 'upn', 'type', 'enabled', 'licenses', 'lastSignIn', 'created'); rows = @($rows | ForEach-Object {
                        [ordered]@{ name = $_.u.displayName; upn = $_.u.userPrincipalName; type = $_.u.userType; enabled = [string][bool]$_.u.accountEnabled
                            licenses = @($_.u.assignedLicenses).Count; lastSignIn = (Format-KitDate $_.last); created = (Format-KitDate $_.u.createdDateTime) } }) })
            findings = $findings
        }
    }
}
