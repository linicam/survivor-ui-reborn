# Upload-Diagnostics.ps1
# Uploads the latest completed SurvivorUI Reborn diagnostic session to
# the private linicam/survivor-ui-reborn-diagnostics repository using
# the already-authenticated GitHub CLI. The SavedVariables file is
# parsed as data only (no Lua execution, no Invoke-Expression).
param([switch]$SelfTest)
$ErrorActionPreference = "Stop"
$Repo = "linicam/survivor-ui-reborn-diagnostics"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "helper-config.json"

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------- Safe Lua-table parser (data only) ----------
$script:Src = ""
$script:Pos = 0
function SkipWs {
    while ($script:Pos -lt $script:Src.Length) {
        $c = $script:Src[$script:Pos]
        if ($c -match '\s') { $script:Pos++ }
        elseif ($c -eq '-' -and $script:Pos + 1 -lt $script:Src.Length -and $script:Src[$script:Pos+1] -eq '-') {
            while ($script:Pos -lt $script:Src.Length -and $script:Src[$script:Pos] -ne "`n") { $script:Pos++ }
        } else { break }
    }
}
function ParseString {
    $quote = $script:Src[$script:Pos]; $script:Pos++
    $sb = New-Object System.Text.StringBuilder
    while ($script:Pos -lt $script:Src.Length) {
        $c = $script:Src[$script:Pos]
        if ($c -eq '\') {
            $script:Pos++; $e = $script:Src[$script:Pos]
            switch ($e) {
                'n' { [void]$sb.Append("`n") } 't' { [void]$sb.Append("`t") }
                'r' { [void]$sb.Append("`r") } '\' { [void]$sb.Append('\') }
                '"' { [void]$sb.Append('"') } "'" { [void]$sb.Append("'") }
                default {
                    if ($e -match '\d') {
                        $digits = ""
                        while ($script:Pos -lt $script:Src.Length -and $script:Src[$script:Pos] -match '\d' -and $digits.Length -lt 3) {
                            $digits += $script:Src[$script:Pos]; $script:Pos++
                        }
                        $script:Pos--
                        [void]$sb.Append([char][int]$digits)
                    } else { [void]$sb.Append($e) }
                }
            }
            $script:Pos++
        } elseif ($c -eq $quote) { $script:Pos++; return $sb.ToString() }
        else { [void]$sb.Append($c); $script:Pos++ }
    }
    Fail "Unterminated string in SavedVariables file."
}
function ParseValue {
    SkipWs
    $c = $script:Src[$script:Pos]
    if ($c -eq '{') { return ParseTable }
    if ($c -eq '"' -or $c -eq "'") { return ParseString }
    $rest = $script:Src.Substring($script:Pos)
    if ($rest -match '^true\b') { $script:Pos += 4; return $true }
    if ($rest -match '^false\b') { $script:Pos += 5; return $false }
    if ($rest -match '^nil\b') { $script:Pos += 3; return $null }
    if ($rest -match '^-?\d+(\.\d+)?([eE][-+]?\d+)?') {
        $numText = $Matches[0]
        $script:Pos += $numText.Length
        $longVal = 0L
        if ($numText -match '^-?\d+$' -and [long]::TryParse($numText, [ref]$longVal)) { return $longVal }
        return [double]$numText
    }
    Fail "Unexpected token at position $($script:Pos) in SavedVariables file."
}
$script:Depth = 0
function ParseTable {
    $script:Depth++
    if ($script:Depth -gt 32) { Fail "SavedVariables nesting exceeds 32 levels; refusing to parse." }
    $script:Pos++ # {
    $arr = New-Object System.Collections.ArrayList
    $map = [ordered]@{}
    $numericKeys = @{}
    $hasStringKey = $false
    while ($true) {
        SkipWs
        if ($script:Pos -ge $script:Src.Length) { Fail "Unterminated table in SavedVariables file." }
        if ($script:Src[$script:Pos] -eq '}') { $script:Pos++; break }
        $key = $null
        if ($script:Src[$script:Pos] -eq '[') {
            $script:Pos++; $key = ParseValue; SkipWs
            if ($script:Src[$script:Pos] -ne ']') { Fail "Expected ] in table key." }
            $script:Pos++; SkipWs
            if ($script:Src[$script:Pos] -ne '=') { Fail "Expected = after table key." }
            $script:Pos++
        } else {
            $rest = $script:Src.Substring($script:Pos)
            if ($rest -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=') {
                $key = $Matches[1]; $script:Pos += $Matches[0].Length
            }
        }
        $val = ParseValue
        if ($null -ne $key) {
            if ($key -is [long] -or $key -is [int]) { $numericKeys[[int]$key] = $val }
            else { $hasStringKey = $true; $map[[string]$key] = $val }
        } else { [void]$arr.Add($val) }
        SkipWs
        if ($script:Pos -lt $script:Src.Length -and ($script:Src[$script:Pos] -eq ',' -or $script:Src[$script:Pos] -eq ';')) { $script:Pos++ }
    }
    $script:Depth--
    if (-not $hasStringKey) {
        # Pure array: positional entries plus explicit numeric keys.
        foreach ($k in ($numericKeys.Keys | Sort-Object)) {
            while ($arr.Count -lt $k - 1) { [void]$arr.Add($null) }
            if ($arr.Count -eq $k - 1) { [void]$arr.Add($numericKeys[$k]) } else { $arr[$k - 1] = $numericKeys[$k] }
        }
        return ,$arr.ToArray()
    }
    foreach ($k in $numericKeys.Keys) { $map[[string]$k] = $numericKeys[$k] }
    for ($i = 0; $i -lt $arr.Count; $i++) { $map[[string]($i + 1)] = $arr[$i] }
    return $map
}
function ParseDiagnostics($text) {
    $idx = $text.IndexOf("SurvivorUIRebornDiagnostics")
    if ($idx -lt 0) { Fail "SurvivorUIRebornDiagnostics not found in the selected file." }
    $eq = $text.IndexOf("=", $idx)
    $script:Src = $text; $script:Pos = $eq + 1
    return ParseValue
}

# ---------- Locate SavedVariables ----------
function Find-SavedVariables {
    # Remembered path first: no recursive scan when it still works.
    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            if ($cfg.SavedVariablesPath -and (Test-Path $cfg.SavedVariablesPath) -and
                (Select-String -Path $cfg.SavedVariablesPath -Pattern "SurvivorUIRebornDiagnostics" -Quiet)) {
                return $cfg.SavedVariablesPath
            }
        } catch {}
    }
    $candidates = @()
    $roots = @("$env:USERPROFILE", "C:\Games", "D:\Games", "C:\Program Files", "C:\Program Files (x86)")
    foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Recurse -Filter "SurvivorUI.lua" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'SavedVariables' } |
                ForEach-Object { $candidates += $_.FullName }
        }
    }
    $valid = @($candidates | Where-Object { (Test-Path $_) -and (Select-String -Path $_ -Pattern "SurvivorUIRebornDiagnostics" -Quiet) })
    if ($valid.Count -eq 1) { return $valid[0] }
    if ($valid.Count -gt 1) {
        Write-Host "Multiple diagnostic files found:"
        for ($i = 0; $i -lt $valid.Count; $i++) { Write-Host "  [$i] $($valid[$i])" }
        $choice = Read-Host "Enter the number to use"
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 0 -and $idx -lt $valid.Count) { return $valid[$idx] }
        Fail "Invalid selection."
    }
    Write-Host "Could not find the diagnostic SavedVariables file automatically."
    $picked = Read-Host "Enter the full path to SurvivorUI.lua in your SavedVariables folder"
    if (-not (Test-Path $picked)) { Fail "File not found: $picked" }
    return $picked
}

# ---------- GitHub upload ----------
function GhApi($method, $path, $bodyObj) {
    $args = @("api", "--method", $method, $path)
    $tmp = $null
    try {
        if ($null -ne $bodyObj) {
            $tmp = [System.IO.Path]::GetTempFileName()
            ($bodyObj | ConvertTo-Json -Depth 10 -Compress) | Set-Content -Path $tmp -Encoding UTF8
            $args += @("--input", $tmp)
        }
        $out = & gh @args 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        if ($out) { return ($out | ConvertFrom-Json) }
        return $true
    } finally {
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}
function Sha256Hex($text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLower()
}
function WriteExactText($path, $contentText) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $contentText, $utf8NoBom)
}
function GetRemoteText($path) {
    $res = GhApi "GET" "repos/$Repo/contents/$path"
    if ($null -eq $res -or -not $res.content) { return $null }
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($res.content -replace '\s', '')))
}
function PutFile($path, $contentText, $message) {
    $existingText = GetRemoteText $path
    if ($null -ne $existingText -and (Sha256Hex $existingText) -eq (Sha256Hex $contentText)) {
        return # identical: no unnecessary commit
    }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($contentText))
    $existing = GhApi "GET" "repos/$Repo/contents/$path"
    $body = @{ message = $message; content = $b64 }
    if ($existing -and $existing.sha) { $body.sha = $existing.sha }
    $res = GhApi "PUT" "repos/$Repo/contents/$path" $body
    if ($null -eq $res) { Fail "Upload failed for $path. Check your connection and run the script again." }
}

# ---------- Main ----------
$BaseDir = "sessions"
if ($SelfTest) { $BaseDir = "test" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "GitHub CLI (gh) was not found. Install it and run: gh auth login" }
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "GitHub CLI is not authenticated. Run: gh auth login" }
$repoInfo = GhApi "GET" "repos/$Repo"
if ($null -eq $repoInfo) { Fail "Repository $Repo was not found or is not accessible." }
if (-not $repoInfo.private) { Fail "Repository $Repo is public. Refusing to upload diagnostics to a public repository." }

$svPath = $null
if ($SelfTest) {
    $svPath = Join-Path $ScriptDir "selftest-SavedVariables.lua"
    $fixture = @'
SurvivorUIRebornDiagnostics = {
    ["schema"] = 1,
    ["order"] = { [1] = "selftest-001" },
    ["sessions"] = {
        ["selftest-001"] = {
            ["id"] = "selftest-001", ["schema"] = 1, ["status"] = "completed",
            ["addonCommit"] = "selftest", ["startedAt"] = 1, ["endedAt"] = 2,
            ["events"] = {
                [1] = { ["seq"] = 1, ["type"] = "abilities_update", ["data"] = { ["name"] = "神圣战马", ["rank"] = 3 } },
                [2] = { ["seq"] = 2, ["type"] = "curse_banner", ["data"] = { ["text"] = "Проклятие тяготеет над тобой: орда накатывает волной (20 с)!" } },
                [3] = { ["seq"] = 3, ["type"] = "jewelry_update", ["data"] = { ["items"] = { [1] = { ["name"] = "埃库利亚指环", ["rank"] = 68 } } } },
                [4] = { ["seq"] = 4, ["type"] = "tooltip", ["data"] = { ["lines"] = { [1] = "Upgrades: +10% damage" } } },
            },
        },
    },
}
'@
    Set-Content -Path $svPath -Value $fixture -Encoding UTF8
} else {
    $svPath = Find-SavedVariables
    @{ SavedVariablesPath = $svPath } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}
if ((Get-Item $svPath).Length -gt 67108864) { Fail "SavedVariables file exceeds the 64 MB parser limit." }
$text = Get-Content $svPath -Raw -Encoding UTF8
$db = ParseDiagnostics $text
if (-not $db.sessions -or -not $db.order -or $db.order.Count -eq 0) { Fail "No diagnostic sessions found. In game, run /sui reborn record start, play, then /sui reborn record stop." }

$sessionId = $null
$recoveredActive = $false
for ($i = $db.order.Count - 1; $i -ge 0; $i--) {
    $s = $db.sessions[$db.order[$i]]
    if ($s.status -eq "active") { $sessionId = $db.order[$i]; $recoveredActive = $true; break }
    if ($s.status -eq "completed" -or $s.status -eq "truncated" -or $s.status -eq "interrupted") { $sessionId = $db.order[$i]; break }
}
if (-not $sessionId) { Fail "No completed or recoverable session found. Stop recording in game first (/sui reborn record stop)." }
if ($sessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Fail "Session ID '$sessionId' contains unsafe characters; refusing to use it in paths." }
$session = $db.sessions[$sessionId]
$events = @($session.events)
$runs = @($events | ForEach-Object { $_.run } | Where-Object { $_ } | Select-Object -Unique).Count

if ($SelfTest) {
    function AssertSelfTest($condition, $message) {
        if (-not $condition) { Fail "SELF-TEST FAIL: $message" }
    }
    AssertSelfTest ($db.order.Count -eq 1) "order must be a single-element array"
    AssertSelfTest ($db.order[0] -eq "selftest-001") "order[0] must be selftest-001"
    AssertSelfTest ($events.Count -eq 4) "event count must be 4"
    AssertSelfTest ($events[0].seq -eq 1 -and $events[0].type -eq "abilities_update") "event 1 order/type mismatch"
    AssertSelfTest ($events[1].seq -eq 2 -and $events[1].type -eq "curse_banner") "event 2 order/type mismatch"
    AssertSelfTest ($events[2].seq -eq 3 -and $events[2].type -eq "jewelry_update") "event 3 order/type mismatch"
    AssertSelfTest ($events[3].seq -eq 4 -and $events[3].type -eq "tooltip") "event 4 order/type mismatch"
    AssertSelfTest ($events[0].data["name"] -eq "神圣战马") "Chinese ability name was not preserved"
    AssertSelfTest ($events[1].data["text"] -like "*Проклятие*") "Russian curse text was not preserved"
    AssertSelfTest ($events[2].data["items"].Count -eq 1) "jewelry items must remain a single-element array"
    AssertSelfTest ($events[2].data["items"][0]["name"] -eq "埃库利亚指环") "Chinese jewelry name was not preserved"
    AssertSelfTest ($events[3].data["lines"].Count -eq 1) "tooltip lines must remain a single-element array"
    AssertSelfTest ($events[3].data["lines"][0] -eq "Upgrades: +10% damage") "tooltip line was not preserved"
}

$exportDir = Join-Path $ScriptDir ("export\" + $sessionId)
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

$files = @{}
$exportStatus = $session.status
if ($recoveredActive) { $exportStatus = "recovered" }
$meta = [ordered]@{
    sessionId = $sessionId; schema = $session.schema; status = $exportStatus
    originalStatus = $session.status; recovered = [bool]$recoveredActive; incomplete = [bool]$recoveredActive
    addonVersion = $session.addonVersion; addonCommit = $session.addonCommit
    gameLanguage = $session.gameLanguage; class = $session.class
    startedAt = $session.startedAt; endedAt = $session.endedAt
    truncated = [bool]$session.truncated; eventCount = $events.Count; runCount = $runs
}
$files["metadata.json"] = $meta | ConvertTo-Json -Depth 10
$chunkSize = 500
$chunkIndex = 0
for ($i = 0; $i -lt $events.Count; $i += $chunkSize) {
    $chunkIndex++
    $slice = $events[$i..([Math]::Min($i + $chunkSize - 1, $events.Count - 1))]
    $files[("events-{0:D3}.json" -f $chunkIndex)] = ConvertTo-Json -InputObject ([object[]]@($slice)) -Depth 20
}
$summary = "# Diagnostic session $sessionId`n`n- Status: $exportStatus`n- Original status: $($session.status)`n- Recovered active session: $([bool]$recoveredActive)`n- Addon commit: $($session.addonCommit)`n- Events: $($events.Count)`n- Runs: $runs`n- Truncated: $($session.truncated)`n"
$files["summary.md"] = $summary

$manifest = [ordered]@{ sessionId = $sessionId; files = @{} }
foreach ($name in $files.Keys) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($files[$name])
    $sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLower()
    $manifest.files[$name] = $sha
    WriteExactText (Join-Path $exportDir $name) $files[$name]
}
$files["manifest.json"] = $manifest | ConvertTo-Json -Depth 10
WriteExactText (Join-Path $exportDir "manifest.json") $files["manifest.json"]

$base = "$BaseDir/$sessionId"
# Identity collision: a completed remote session with different
# contents must never be overwritten silently.
$remoteManifestText = GetRemoteText "$base/manifest.json"
if ($null -ne $remoteManifestText) {
    $remoteManifest = $remoteManifestText | ConvertFrom-Json
    $conflict = $false
    foreach ($name in $manifest.files.Keys) {
        if ($remoteManifest.files.$name -and $remoteManifest.files.$name -ne $manifest.files[$name]) { $conflict = $true }
    }
    if ($conflict) { Fail "Session $sessionId already exists remotely with different contents. Refusing to overwrite; investigate the collision." }
}
foreach ($name in $files.Keys) {
    if ($name -ne "manifest.json") { PutFile "$base/$name" $files[$name] "diagnostics: $sessionId $name" }
}
# Manifest last: its presence marks a complete upload.
PutFile "$base/manifest.json" $files["manifest.json"] "diagnostics: $sessionId manifest"
# Verify every uploaded file's remote hash, not just manifest existence.
foreach ($name in $manifest.files.Keys) {
    $remoteText = GetRemoteText "$base/$name"
    if ($null -eq $remoteText -or (Sha256Hex $remoteText) -ne $manifest.files[$name]) {
        Fail "Verification failed for $base/$name. Run the script again to retry."
    }
}

if (-not $SelfTest) {
    $existingLatestText = GetRemoteText "latest.json"
    $updateLatest = $true
    if ($null -ne $existingLatestText) {
        try {
            $existingLatest = $existingLatestText | ConvertFrom-Json
            if ($existingLatest.startedAt -and $session.startedAt -and [double]$existingLatest.startedAt -gt [double]$session.startedAt) {
                $updateLatest = $false
            }
        } catch {}
    }
    if ($updateLatest) {
        $latest = [ordered]@{ sessionId = $sessionId; path = $base; addonCommit = $session.addonCommit; eventCount = $events.Count; runCount = $runs; startedAt = $session.startedAt }
        PutFile "latest.json" ($latest | ConvertTo-Json -Depth 10) "diagnostics: latest $sessionId"
    }
}

Write-Host ""
if ($SelfTest) { Write-Host "SELF-TEST PASS" }
Write-Host "Diagnostic upload completed."
if ($recoveredActive) { Write-Host "Recovered active session: normal finalization was not observed; exported as incomplete." }
Write-Host ""
Write-Host "Session: $sessionId"
Write-Host "Addon commit: $($session.addonCommit)"
Write-Host "Runs recorded: $runs"
Write-Host "Events uploaded: $($events.Count)"
Write-Host ""
Write-Host "GitHub:"
Write-Host "https://github.com/$Repo/tree/main/$base"
Write-Host "Local export: $exportDir"
