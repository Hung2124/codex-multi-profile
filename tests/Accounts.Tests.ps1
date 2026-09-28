#Requires -Version 5.1
# Account store, switching, masking and page-message validation, on a throwaway root + CODEX_HOME.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts\CodexAccounts.psm1') -Force

function Assert([bool]$Cond, [string]$Msg) { if (-not $Cond) { throw "FAIL: $Msg" } }
function Assert-Throws([scriptblock]$Block, [string]$Msg) {
    $threw = $false
    try { & $Block } catch { $threw = $true }
    if (-not $threw) { throw "FAIL (no error): $Msg" }
}
function ConvertTo-B64Url([string]$Text) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function New-FakeAuth([string]$Path, [string]$Email, [string]$AccountId, [string]$Refresh = 'r1') {
    $claims = @{ email = $Email; 'https://api.openai.com/auth' = @{ chatgpt_account_id = $AccountId; chatgpt_plan_type = 'plus' } } | ConvertTo-Json -Compress
    $jwt = (ConvertTo-B64Url '{"alg":"none"}') + '.' + (ConvertTo-B64Url $claims) + '.sig'
    $obj = [ordered]@{ OPENAI_API_KEY = $null; tokens = [ordered]@{ id_token = $jwt; access_token = 'a'; refresh_token = $Refresh; account_id = $AccountId } }
    Write-Utf8NoBom -Path $Path -Text ($obj | ConvertTo-Json -Depth 5)
}

$tmp = Join-Path $env:TEMP ('cmp-acc-' + [guid]::NewGuid().ToString('n'))
$R = Join-Path $tmp 'root'
$H = Join-Path $tmp 'codex-home'
$live = Join-Path $H 'auth.json'
try {
    New-Item -ItemType Directory -Force -Path $R, $H | Out-Null

    # --- names: accents dropped, same rule as the page ("Cong viec" with Vietnamese marks -> cong-viec)
    $viet = 'C' + [char]0x00F4 + 'ng vi' + [char]0x1EC7 + 'c ' + [char]0x0110 + [char]0x1EA1 + 'i'
    Assert ((ConvertTo-AccountKey -Name $viet) -eq 'cong-viec-dai') 'accented name -> cong-viec-dai'
    Assert ((ConvertTo-AccountKey -Name '  Work #2 ') -eq 'work-2') 'punctuation -> dashes'
    Assert-Throws { ConvertTo-AccountKey -Name '!!!' } 'empty key rejected'

    # --- identity + masking
    New-FakeAuth -Path $live -Email 'alice.smith@example.com' -AccountId 'acc-a'
    $id = Get-AuthIdentity -Path $live
    Assert ($id.Email -eq 'alice.smith@example.com' -and $id.AccountId -eq 'acc-a' -and $id.Plan -eq 'plus') 'identity from id_token'
    Assert ((Hide-AuthEmail -Email $id.Email) -eq 'al***@example.com') 'masked email'
    Assert ($null -eq (Get-AuthIdentity -Path (Join-Path $H 'missing.json'))) 'missing auth -> $null'

    # --- save: first login becomes "main", the same login twice is refused
    $n = Save-CodexAccount -Root $R -CodexHome $H
    Assert ($n -eq 'main') 'first auto name is main'
    Assert-Throws { Save-CodexAccount -Name 'again' -Root $R -CodexHome $H } 'same login saved twice'
    Assert ((Get-CodexActiveAccount -Root $R -CodexHome $H).Name -eq 'main') 'active = main'

    # --- add a second account (Clear -> "sign in" -> save under the chosen name)
    Clear-CodexLiveAuth -Root $R -CodexHome $H
    Assert (-not (Test-Path -LiteralPath $live)) 'live auth cleared for sign-in'
    Assert (Test-Path -LiteralPath (Join-Path $R 'accounts\main\auth.json')) 'main kept while signed out'
    New-FakeAuth -Path $live -Email 'bob@example.org' -AccountId 'acc-b'
    Assert ((Save-CodexAccount -Name 'Work' -Root $R -CodexHome $H) -eq 'work') 'second account saved as work'

    # --- Codex rotates tokens in place; switching away must keep the fresh copy
    New-FakeAuth -Path $live -Email 'bob@example.org' -AccountId 'acc-b' -Refresh 'r2-rotated'
    Set-CodexLiveAuth -Name 'main' -Root $R -CodexHome $H
    Assert ((Get-AuthIdentity -Path $live).Email -eq 'alice.smith@example.com') 'switched to main'
    $workSaved = Get-Content -LiteralPath (Join-Path $R 'accounts\work\auth.json') -Raw
    Assert ($workSaved -match 'r2-rotated') 'outgoing account synced before the switch'
    New-FakeAuth -Path $live -Email 'alice.smith@example.com' -AccountId 'acc-a' -Refresh 'r3'
    Assert ((Sync-CodexActiveAccount -Root $R -CodexHome $H) -eq 'main') 'sync returns the active account'
    Assert ((Get-Content -LiteralPath (Join-Path $R 'accounts\main\auth.json') -Raw) -match 'r3') 'periodic sync keeps main fresh'

    # --- same email, other workspace = other account
    $other = Join-Path $tmp 'other.json'
    New-FakeAuth -Path $other -Email 'alice.smith@example.com' -AccountId 'acc-team'
    Assert ($null -eq (Find-CodexAccountByIdentity -Identity (Get-AuthIdentity -Path $other) -Root $R)) 'workspace id separates accounts'

    # --- rename / remove
    Assert ((Rename-CodexAccount -Name 'work' -NewName 'Job' -Root $R) -eq 'job') 'rename'
    Assert-Throws { Rename-CodexAccount -Name 'job' -NewName 'main' -Root $R } 'rename onto an existing name'
    Assert-Throws { Remove-CodexAccount -Name 'main' -Root $R -CodexHome $H } 'the account in use cannot be removed'
    Set-CodexAccountMeta -Name 'job' -Root $R -Depleted $true
    Assert ((Get-CodexAccounts -Root $R | Where-Object Name -eq 'job').Depleted) 'depleted flag stored'

    # --- page snapshot: masked only, flags right
    $snap = Get-CodexSwitcherSnapshot -Root $R -CodexHome $H -Pending 'new-one'
    $json = $snap | ConvertTo-Json -Depth 6 -Compress
    Assert (-not (Test-CodexTextHasFullEmail -Text $json)) 'snapshot has no unmasked email'
    Assert ($json -notmatch 'r3|refresh|access_token|id_token') 'snapshot has no tokens'
    Assert ($snap.active -eq 'main' -and $snap.signedIn -and $snap.pending -eq 'new-one') 'snapshot active/signedIn/pending'
    Assert ($null -eq $snap.suggestion) 'no suggestion when the only other account is out of quota'
    Assert (Test-CodexTextHasFullEmail -Text 'x alice@example.com') 'full email detected'

    # --- usage bars: /wham/usage parsing, depleted when a limit is reached, numbers only in the snapshot
    $plus = '{"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":12.6,"limit_window_seconds":18000,"reset_after_seconds":900,"reset_at":1790645148},"secondary_window":{"used_percent":6,"limit_window_seconds":604800,"reset_after_seconds":4000,"reset_at":1791050947}}}'
    $free = '{"plan_type":"free","rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":100,"limit_window_seconds":2592000,"reset_after_seconds":5,"reset_at":1793219149},"secondary_window":null}}'
    $up = ConvertFrom-CodexUsageJson -Json $plus
    Assert ($up.windows.Count -eq 2 -and $up.windows[0].label -eq '5h' -and $up.windows[0].used -eq 13 -and $up.windows[1].label -eq 'week') 'plus: 5h + week windows'
    Assert (-not $up.limitReached) 'plus: not limited'
    Assert (($up.windows[1].label -is [string]) -and ($up.windows[1].label -ceq 'week')) 'one label per window (switch returned week AND 7d once)'
    $uf = ConvertFrom-CodexUsageJson -Json $free
    Assert ($uf.windows.Count -eq 1 -and $uf.windows[0].label -eq 'month' -and $uf.limitReached) 'free: month window, limit reached'
    $snapU = Get-CodexSwitcherSnapshot -Root $R -CodexHome $H -Usage @{ main = $up; job = $uf }
    $pj = @($snapU.profiles | Where-Object { $_.name -eq 'job' })[0]
    $pm = @($snapU.profiles | Where-Object { $_.name -eq 'main' })[0]
    Assert ($pm.usage.Count -eq 2 -and $pj.depleted) 'usage in snapshot; limit reached shows as out of quota'
    Assert (($snapU | ConvertTo-Json -Depth 8 -Compress) -match '"name":"job"[^}]*?"usage":\[') 'a one-window plan still reaches the page as a list'
    Assert ((($snapU | ConvertTo-Json -Depth 8 -Compress)) -notmatch 'token|Bearer') 'usage snapshot carries no tokens'
    Assert ($null -eq (New-CodexUsageRequest -AuthPath (Join-Path $tmp 'other.json')).Content) 'usage request has no body'

    Remove-CodexAccount -Name 'job' -Root $R -CodexHome $H
    Assert (@(Get-CodexAccounts -Root $R).Count -eq 1) 'removed'

    # --- a login that is not saved is never dropped
    New-FakeAuth -Path $live -Email 'carol@example.net' -AccountId 'acc-c'
    Assert-Throws { Clear-CodexLiveAuth -Root $R -CodexHome $H } 'unsaved login is not cleared'
    Assert (Test-Path -LiteralPath $live) 'unsaved login still there'

    # --- page messages: fixed types, known names only
    $known = @('main', 'job')
    $ok = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"job"}' -KnownProfiles $known
    Assert (-not $ok.Error -and $ok.Profile -eq 'job' -and $ok.Value -eq $false) 'valid switch (full restart by default)'
    $fast = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"job","fast":true}' -KnownProfiles $known
    Assert ($fast.Value -eq $true) 'fast switch flag passed through'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"job","fast":"yes"}' -KnownProfiles $known).Value -eq $false) 'non-bool fast flag ignored'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"nope"}' -KnownProfiles $known).Error -eq 'unknown-profile') 'unknown profile'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"..\\x"}' -KnownProfiles $known).Error -eq 'bad-profile') 'path in profile'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"exec","cmd":"calc"}' -KnownProfiles $known).Error -eq 'unknown-type') 'unknown type'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload ('x' * 5000) -KnownProfiles $known).Error -eq 'too-large') 'too large'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"add","name":"Main"}' -KnownProfiles $known).Error -eq 'exists') 'add existing name'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"add","name":"***"}' -KnownProfiles $known).Error -eq 'bad-name') 'add bad name'
    Assert ((ConvertFrom-CodexSwitcherMessage -Payload '{"type":"rename","profile":"job","name":"main"}' -KnownProfiles $known).Error -eq 'exists') 'rename onto existing'
    $rn = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"rename","profile":"job","name":"Job 2"}' -KnownProfiles $known
    Assert (-not $rn.Error -and $rn.Name -eq 'job-2') 'valid rename'

    # --- safe delete: never follows a junction (the old profiles linked into ~/.codex)
    $keep = Join-Path $tmp 'keep'
    New-Item -ItemType Directory -Force -Path $keep | Out-Null
    Set-Content -LiteralPath (Join-Path $keep 'precious.txt') -Value 'x'
    $legacy = Join-Path $tmp 'legacy\profiles\p1\.codex'
    New-Item -ItemType Directory -Force -Path $legacy | Out-Null
    cmd.exe /c mklink /J (Join-Path $legacy 'memories') $keep | Out-Null
    Remove-CodexTreeNoFollow -Path (Join-Path $tmp 'legacy')
    Assert (-not (Test-Path -LiteralPath (Join-Path $tmp 'legacy'))) 'legacy tree removed'
    Assert (Test-Path -LiteralPath (Join-Path $keep 'precious.txt')) 'junction target untouched'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'OK: account store, token sync, add/rename/remove, masked snapshot, message validation, junction-safe delete.'
