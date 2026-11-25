# Upload-Diagnostics.ps1
# Uploads the latest completed SurvivorUI Reborn diagnostic session to
# the private linicam/survivor-ui-reborn-diagnostics repository using
# the already-authenticated GitHub CLI. The SavedVariables file is
# parsed as data only (no Lua execution, no Invoke-Expression).
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
        $script:Pos += $Matches[0].Length
        return [double]$Matches[0]
    }
    Fail "Unexpected token at position $($script:Pos) in SavedVariables file."
}
function ParseTable {
    $script:Pos++ # {
    $arr = New-Object System.Collections.ArrayList
    $map = [ordered]@{}
    $isMap = $false
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
        if ($null -ne $key) { $isMap = $true; $map[[string]$key] = $val } else { [void]$arr.Add($val) }
        SkipWs
        if ($script:Pos -lt $script:Src.Length -and ($script:Src[$script:Pos] -eq ',' -or $script:Src[$script:Pos] -eq ';')) { $script:Pos++ }
    }
    if ($isMap) { return $map }
    return $arr.ToArray()
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
    $candidates = @()
    if (Test-Path $ConfigPath) {
        try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json; if ($cfg.SavedVariablesPath) { $candidates += $cfg.SavedVariablesPath } } catch {}
    }
    $roots = @("$env:USERPROFILE", "C:\Games", "D:\Games", "C:\Program Files", "C:\Program Files (x86)")
    foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Recurse -Filter "SurvivorUI.lua" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'SavedVariables' } |
                ForEach-Object { $candidates += $_.FullName }
        }
    }
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and (Select-String -Path $c -Pattern "SurvivorUIRebornDiagnostics" -Quiet)) { return $c }
    }
    Write-Host "Could not find the diagnostic SavedVariables file automatically."
    $picked = Read-Host "Enter the full path to SurvivorUI.lua in your SavedVariables folder"
    if (-not (Test-Path $picked)) { Fail "File not found: $picked" }
    return $picked
}

# ---------- GitHub upload ----------
function GhApi($method, $path, $bodyObj) {
    $args = @("api", "--method", $method, $path)
    if ($null -ne $bodyObj) {
        $tmp = [System.IO.Path]::GetTempFileName()
        ($bodyObj | ConvertTo-Json -Depth 10 -Compress) | Set-Content -Path $tmp -Encoding UTF8
        $args += @("--input", $tmp)
    }
    $out = & gh @args 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($out) { return ($out | ConvertFrom-Json) }
    return $true
}
function PutFile($path, $contentText, $message) {
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($contentText))
    $existing = GhApi "GET" "repos/$Repo/contents/$path"
    $body = @{ message = $message; content = $b64 }
    if ($existing -and $existing.sha) { $body.sha = $existing.sha }
    $res = GhApi "PUT" "repos/$Repo/contents/$path" $body
    if ($null -eq $res) { Fail "Upload failed for $path. Check your connection and run the script again." }
}

# ---------- Main ----------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "GitHub CLI (gh) was not found. Install it and run: gh auth login" }
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "GitHub CLI is not authenticated. Run: gh auth login" }
$repoInfo = GhApi "GET" "repos/$Repo"
if ($null -eq $repoInfo) { Fail "Repository $Repo was not found or is not accessible." }
if (-not $repoInfo.private) { Fail "Repository $Repo is public. Refusing to upload diagnostics to a public repository." }

$svPath = Find-SavedVariables
@{ SavedVariablesPath = $svPath } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
$text = Get-Content $svPath -Raw -Encoding UTF8
$db = ParseDiagnostics $text
if (-not $db.sessions -or -not $db.order -or $db.order.Count -eq 0) { Fail "No diagnostic sessions found. In game, run /sui reborn record start, play, then /sui reborn record stop." }

$sessionId = $null
for ($i = $db.order.Count - 1; $i -ge 0; $i--) {
    $s = $db.sessions[$db.order[$i]]
    if ($s.status -eq "completed" -or $s.status -eq "truncated" -or $s.status -eq "interrupted") { $sessionId = $db.order[$i]; break }
}
if (-not $sessionId) { Fail "No completed session found. Stop recording in game first (/sui reborn record stop)." }
$session = $db.sessions[$sessionId]
$events = @($session.events)
$runs = @($events | ForEach-Object { $_.run } | Where-Object { $_ } | Select-Object -Unique).Count

$exportDir = Join-Path $ScriptDir ("export\" + $sessionId)
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

$files = @{}
$meta = [ordered]@{
    sessionId = $sessionId; schema = $session.schema; status = $session.status
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
    $files[("events-{0:D3}.json" -f $chunkIndex)] = @($slice) | ConvertTo-Json -Depth 20
}
$summary = "# Diagnostic session $sessionId`n`n- Status: $($session.status)`n- Addon commit: $($session.addonCommit)`n- Events: $($events.Count)`n- Runs: $runs`n- Truncated: $($session.truncated)`n"
$files["summary.md"] = $summary

$manifest = [ordered]@{ sessionId = $sessionId; files = @{} }
foreach ($name in $files.Keys) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($files[$name])
    $sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace("-", "").ToLower()
    $manifest.files[$name] = $sha
    Set-Content -Path (Join-Path $exportDir $name) -Value $files[$name] -Encoding UTF8
}
$files["manifest.json"] = $manifest | ConvertTo-Json -Depth 10
Set-Content -Path (Join-Path $exportDir "manifest.json") -Value $files["manifest.json"] -Encoding UTF8

$base = "sessions/$sessionId"
foreach ($name in $files.Keys) {
    if ($name -ne "manifest.json") { PutFile "$base/$name" $files[$name] "diagnostics: $sessionId $name" }
}
# Manifest last: its presence marks a complete upload.
PutFile "$base/manifest.json" $files["manifest.json"] "diagnostics: $sessionId manifest"
$verify = GhApi "GET" "repos/$Repo/contents/$base/manifest.json"
if ($null -eq $verify) { Fail "Upload verification failed. Run the script again to retry." }

$latest = [ordered]@{ sessionId = $sessionId; path = $base; addonCommit = $session.addonCommit; eventCount = $events.Count; runCount = $runs }
PutFile "latest.json" ($latest | ConvertTo-Json -Depth 10) "diagnostics: latest $sessionId"

Write-Host ""
Write-Host "Diagnostic upload completed."
Write-Host ""
Write-Host "Session: $sessionId"
Write-Host "Addon commit: $($session.addonCommit)"
Write-Host "Runs recorded: $runs"
Write-Host "Events uploaded: $($events.Count)"
Write-Host ""
Write-Host "GitHub:"
Write-Host "https://github.com/$Repo/tree/main/$base"
Write-Host "Local export: $exportDir"
