@{
    Id = 'apps'; Title = 'App registrations'; Icon = '🧩'; Order = 80; Target = 'graph'
    Run = {
        $apps = @(Invoke-Graph '/applications?$select=id,displayName,appId,createdDateTime,passwordCredentials,keyCredentials,signInAudience&$top=999' -All)
        $now = Get-Date
        $creds = foreach ($a in $apps) {
            foreach ($c in @($a.passwordCredentials)) { if ($c) { [pscustomobject]@{ app = $a.displayName; kind = 'Secret'; name = $c.displayName; end = (ConvertTo-KitDate $c.endDateTime) } } }
            foreach ($c in @($a.keyCredentials)) { if ($c) { [pscustomobject]@{ app = $a.displayName; kind = 'Certificate'; name = $c.displayName; end = (ConvertTo-KitDate $c.endDateTime) } } }
        }
        $creds = @($creds | ForEach-Object { $_ | Add-Member days ([int]($_.end - $now).TotalDays) -PassThru })
        $expired = @($creds | Where-Object { $_.days -lt 0 }); $soon = @($creds | Where-Object { $_.days -ge 0 -and $_.days -le 30 })
        $findings = @()
        if ($expired.Count) { $findings += New-KitFinding medium "$($expired.Count) app credential(s) have expired." }
        if ($soon.Count) { $findings += New-KitFinding high "$($soon.Count) app credential(s) expire within 30 days." }
        $multi = @($apps | Where-Object { $_.signInAudience -eq 'AzureADandPersonalMicrosoftAccount' -or $_.signInAudience -eq 'AzureADMultipleOrgs' })
        @{
            summary = @(
                @{ label = 'App registrations'; value = $apps.Count }
                @{ label = 'Credentials'; value = $creds.Count }
                @{ label = 'Expiring <30d'; value = $soon.Count; tone = $(if ($soon.Count) { 'bad' } else { 'good' }) }
                @{ label = 'Expired'; value = $expired.Count; tone = $(if ($expired.Count) { 'warn' } else { 'good' }) }
                @{ label = 'Multi-tenant apps'; value = $multi.Count }
            )
            charts = @(
                @{ title = 'Credential health'; type = 'donut'; items = @(@{ label = 'Healthy'; value = $creds.Count - $expired.Count - $soon.Count }, @{ label = 'Expiring <30d'; value = $soon.Count }, @{ label = 'Expired'; value = $expired.Count }) }
                @{ title = 'Sign-in audience'; type = 'donut'; items = (New-KitItems $apps 'signInAudience') }
            )
            tables = @(@{ title = 'Credentials by expiry'; columns = @('app', 'type', 'name', 'expires', 'daysLeft'); rows = @($creds | Sort-Object days | ForEach-Object {
                        [ordered]@{ app = $_.app; type = $_.kind; name = $_.name; expires = (Format-KitDate $_.end); daysLeft = $_.days } }) })
            findings = $findings
        }
    }
}
