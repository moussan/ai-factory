# AI Factory — MS-AD-Kit

A self-contained Windows tool that signs in with an admin account, queries a Microsoft tenant
(Entra ID / Microsoft 365 / Intune / Azure) and shows it on a live dashboard — in the spirit of AWS-Lens
style cloud explorers, but Microsoft-only.

* **Nothing to install.** Pure PowerShell 5.1+ (built into Windows) calling Microsoft Graph and Azure ARM over REST. No Graph/Az modules, no Node, no CDN — the dashboard works offline.
* **Read-only.** Only `GET` requests, delegated *read* permissions, tokens kept in memory only.
* **Query anything.** The *Query explorer* tab runs any Graph / Azure GET endpoint the signed-in account may read, with table view and CSV export.
* **Easy to update.** `.\MS-AD-Kit.ps1 -Update` (or the dashboard's ⬆ button) pulls new collectors, dashboard and scripts from GitHub. Your `config.json` and `collectors\custom\` are never touched.

## Quick start

```powershell
.\Start-MSADKit.cmd            # or: .\MS-AD-Kit.ps1
.\MS-AD-Kit.ps1 -Azure         # also sign in to Azure (subscriptions, resources)
.\MS-AD-Kit.ps1 -Demo          # fictional tenant, no sign-in — try the dashboard
.\MS-AD-Kit.ps1 -Cached        # reopen last results without signing in
.\MS-AD-Kit.ps1 -Export r.html # one shareable HTML file (data embedded)
.\MS-AD-Kit.ps1 -TenantId contoso.onmicrosoft.com
```

A browser code (device-code flow) is shown and copied to your clipboard; sign in with an admin
account. Global Reader + Security Reader (+ Reports Reader) gives the fullest picture.
A tenant admin may need to **grant consent** for the requested read scopes the first time
(see `config.default.json`). If a section lacks permission/licence it shows the error and the rest still works.

## What it shows

Tenant & domains · Users (stale, guests, disabled) · Licenses (unassigned seats) · Groups · Admin roles ·
MFA registration · Conditional Access · App-registration secret/cert expiry · Entra devices · Intune compliance ·
Secure Score & risky users · 24h sign-ins · Service health · M365 activity · Azure subscriptions/resources.
The Overview ranks **findings** (high → low) across all sections.

## Add or change a data source

Each file in `collectors\` is one dashboard section. Drop your own into `collectors\custom\`:

```powershell
@{
  Id = 'teams'; Title = 'Teams'; Icon = '💬'; Order = 140; Target = 'graph'   # or 'arm'
  Run = {
    $t = @(Invoke-Graph '/teams' -All)            # also: -Beta, -Raw, -Max N;  Invoke-Arm for Azure
    @{
      summary  = @(@{ label = 'Teams'; value = $t.Count })
      charts   = @(@{ title = 'By visibility'; type = 'donut'; items = (New-KitItems $t 'visibility') })  # donut | bar | line
      tables   = @(@{ title = 'Teams'; columns = @('name'); rows = @($t | % { [ordered]@{ name = $_.displayName } }) })
      findings = @((New-KitFinding medium 'Something to look at'))   # high|medium|low|info|good
    }
  }
}
```
No dashboard change is needed — sections, KPIs, charts, tables and findings are rendered generically.

## Updating

`config.json` → `update.repo` / `update.branch` (default `moussan/ai-factory` @ `main`). For a private repo set the
`MSADKIT_GH_TOKEN` environment variable to a token with read access. Check `version.json` for the installed commit.

## Files

```
MS-AD-Kit.ps1  Start-MSADKit.cmd  config.default.json
lib/        Auth (device code) · Api (Graph/ARM) · Server (localhost) · Update
collectors/ one file per section      collectors/custom/ yours (never overwritten)
dashboard/  index.html · app.js · style.css · demo.js
```

## Security notes

Server binds to `localhost` only, checks the Host header, and requires a per-session token on every API call.
Collected data is written to `data\last.json` — treat it as sensitive tenant data. Exports embed that data too.
Sign-in uses Microsoft's public "Microsoft Graph Command Line Tools" (and Azure PowerShell) client IDs; to use your own
app registration, change `clientId` in `config.json`.

## Status

The dashboard UI is tested in a browser against demo data. The PowerShell scripts were written and reviewed but
**not yet run against a live tenant** — expect small fixes on first real run, and please report them.
