@{
    Id = 'roles'; Title = 'Admin roles'; Icon = '🛡️'; Order = 50; Target = 'graph'
    Run = {
        $roles = @(Invoke-Graph '/directoryRoles' -All)
        $rows = @()
        foreach ($r in $roles) {
            $m = @(Invoke-Graph "/directoryRoles/$($r.id)/members?`$select=id,displayName,userPrincipalName" -All)
            foreach ($x in $m) {
                $rows += [pscustomobject]@{ role = $r.displayName; member = $x.displayName; upn = $x.userPrincipalName; type = ($x.'@odata.type' -replace '#microsoft.graph.', '') }
            }
        }
        $ga = @($rows | Where-Object { $_.role -eq 'Global Administrator' })
        $admins = @($rows | Where-Object { $_.upn } | Select-Object -ExpandProperty upn -Unique)
        $findings = @()
        if ($ga.Count -gt 5) { $findings += New-KitFinding high "$($ga.Count) Global Administrators - Microsoft recommends fewer than 5." }
        elseif ($ga.Count -lt 2) { $findings += New-KitFinding medium "Only $($ga.Count) Global Administrator(s) - keep at least 2 (plus break-glass)." }
        else { $findings += New-KitFinding good "$($ga.Count) Global Administrators - within recommended range." }
        $sp = @($rows | Where-Object { $_.type -eq 'servicePrincipal' -and $_.role -eq 'Global Administrator' })
        if ($sp.Count) { $findings += New-KitFinding high "$($sp.Count) service principal(s) hold Global Administrator." }
        @{
            summary = @(
                @{ label = 'Active roles'; value = $roles.Count }
                @{ label = 'Role assignments'; value = $rows.Count }
                @{ label = 'Unique admins'; value = $admins.Count }
                @{ label = 'Global admins'; value = $ga.Count; tone = $(if ($ga.Count -gt 5) { 'bad' } else { 'good' }) }
            )
            charts = @(@{ title = 'Members per role'; type = 'bar'; items = (New-KitItems $rows 'role' -Top 12) })
            tables = @(@{ title = 'Role assignments (active)'; columns = @('role', 'member', 'upn', 'type'); rows = @($rows | ForEach-Object { [ordered]@{ role = $_.role; member = $_.member; upn = $_.upn; type = $_.type } }) })
            findings = $findings
        }
    }
}
