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
    $gameDirs = @("D:\Azeroth Survivors", "C:\Azeroth Survivors", "D:\Games\Azeroth Survivors", "C:\Games\Azeroth Survivors")
    foreach ($gameDir in $gameDirs) {
        $wtf = Join-Path $gameDir "WTF\Account"
        if (Test-Path $wtf) {
            Get-ChildItem -Path $wtf -Recurse -Filter "SurvivorUI.lua" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'SavedVariables' } |
                ForEach-Object { $candidates += $_.FullName }
        }
    }
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
    $picked = Read-Host "Enter your AZ Reborn installation directory, or the full path to SurvivorUI.lua in SavedVariables"
    if (Test-Path $picked -PathType Container) {
        $found = Get-ChildItem -Path $picked -Recurse -Filter "SurvivorUI.lua" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'SavedVariables' } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
        Fail "No SurvivorUI.lua SavedVariables file found under: $picked"
    }
    if (-not (Test-Path $picked)) { Fail "File not found: $picked" }
    return $picked
}

# ---------- GitHub upload ----------
$script:GhPath = $null
function Quote-NativeArg($arg) {
    $text = [string]$arg
    if ($text -eq "") { return '""' }
    if ($text -notmatch '[\s"]') { return $text }
    return '"' + ($text -replace '\\', '\\' -replace '"', '\"') + '"'
}
function Invoke-GhNative($arguments) {
    # Windows PowerShell 5.1 can turn native stderr into a terminating
    # NativeCommandError under $ErrorActionPreference="Stop". Run gh
    # as a child process with redirected streams instead, and read
    # the exit code explicitly.
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $argString = ($arguments | ForEach-Object { Quote-NativeArg $_ }) -join " "
        $process = Start-Process -FilePath $script:GhPath -ArgumentList $argString `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
            -Wait -PassThru -NoNewWindow
        $stdout = ""
        $stderr = ""
        if (Test-Path $outFile) { $stdout = Get-Content -Path $outFile -Raw -ErrorAction SilentlyContinue }
        if (Test-Path $errFile) { $stderr = Get-Content -Path $errFile -Raw -ErrorAction SilentlyContinue }
        if ($null -eq $stdout) { $stdout = "" }
        if ($null -eq $stderr) { $stderr = "" }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdout
            StdErr = $stderr
        }
    } finally {
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    }
}
function GhApiResult($method, $path, $bodyObj) {
    $ghArgs = @("api", "--method", $method, $path)
    $tmp = $null
    try {
        if ($null -ne $bodyObj) {
            $tmp = [System.IO.Path]::GetTempFileName()
            WriteExactText $tmp ($bodyObj | ConvertTo-Json -Depth 10 -Compress)
            $ghArgs += @("--input", $tmp)
        }
        $result = Invoke-GhNative $ghArgs
        if ($result.ExitCode -eq 0) {
            $data = $true
            if ($result.StdOut -and $result.StdOut.Trim() -ne "") {
                $data = $result.StdOut | ConvertFrom-Json
            }
            return [pscustomobject]@{
                Ok = $true; IsNotFound = $false; StatusCode = 200
                ExitCode = 0; Data = $data; Error = ""
            }
        }
        $combined = ($result.StdErr + "`n" + $result.StdOut).Trim()
        $statusCode = $null
        if ($combined -match 'HTTP\s+(\d{3})') { $statusCode = [int]$Matches[1] }
        return [pscustomobject]@{
            Ok = $false; IsNotFound = ($statusCode -eq 404); StatusCode = $statusCode
            ExitCode = $result.ExitCode; Data = $null; Error = $combined
        }
    } finally {
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}
function GhApi($method, $path, $bodyObj) {
    $result = GhApiResult $method $path $bodyObj
    if ($result.Ok) { return $result.Data }
    if ($result.IsNotFound) { return $null }
    $detail = $result.Error
    if (-not $detail) { $detail = "no error output from gh" }
    throw "GitHub API $method $path failed (exit $($result.ExitCode)): $detail"
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
    if ($null -eq $res) { return $null }
    if ($res.content) {
        return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($res.content -replace '\s', '')))
    }
    # The Contents API returns empty content for files over 1 MB;
    # fetch the same file through the Git Blob API instead.
    if ($res.sha) {
        $blob = GhApi "GET" "repos/$Repo/git/blobs/$($res.sha)"
        if ($blob -and $blob.content) {
            return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($blob.content -replace '\s', '')))
        }
    }
    return $null
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
    if ($null -eq $res) { throw "Upload failed for $path. Check your connection and run the script again." }
}

function ConvertTo-SortedValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [System.Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($key in @($value.Keys | Sort-Object)) {
            $sorted[[string]$key] = ConvertTo-SortedValue $value[$key]
        }
        return $sorted
    }
    if ($value -is [pscustomobject]) {
        $sorted = [ordered]@{}
        foreach ($prop in @($value.PSObject.Properties | Sort-Object Name)) {
            $sorted[$prop.Name] = ConvertTo-SortedValue $prop.Value
        }
        return $sorted
    }
    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
        $items = @()
        foreach ($item in $value) { $items += ,(ConvertTo-SortedValue $item) }
        return ,$items
    }
    return $value
}
function New-EventChunks($events, $maxBytes) {
    $chunks = @()
    $current = @()
    $currentBytes = 2
    foreach ($event in $events) {
        $json = ConvertTo-SortedValue $event | ConvertTo-Json -Depth 30 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($json)
        $extra = $bytes
        if ($current.Count -gt 0) { $extra += 1 }
        if ($current.Count -gt 0 -and ($currentBytes + $extra) -gt $maxBytes) {
            $chunks += ,("[" + ($current -join ",") + "]")
            $current = @()
            $currentBytes = 2
            $extra = $bytes
        }
        $current += ,$json
        $currentBytes += $extra
    }
    if ($current.Count -gt 0 -or $chunks.Count -eq 0) {
        $chunks += ,("[" + ($current -join ",") + "]")
    }
    return ,$chunks
}

# ---------- Main ----------
$BaseDir = "sessions"
if ($SelfTest) { $BaseDir = "test" }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "GitHub CLI (gh) was not found. Install it and run: gh auth login" }
$script:GhPath = (Get-Command gh).Source
$auth = Invoke-GhNative @("auth", "status")
if ($auth.ExitCode -ne 0) {
    $detail = ($auth.StdErr + "`n" + $auth.StdOut).Trim()
    Fail "GitHub CLI is not authenticated. Run: gh auth login. $detail"
}
try {
    $repoInfo = GhApi "GET" "repos/$Repo"
} catch {
    Fail $_.Exception.Message
}
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

$eligible = @()
foreach ($id in $db.order) {
    $s = $db.sessions[$id]
    if ($s.status -eq "active") {
        $eligible += ,@{ Id = $id; RecoveredActive = $true }
    } elseif ($s.status -eq "completed" -or $s.status -eq "truncated" -or $s.status -eq "interrupted") {
        $eligible += ,@{ Id = $id; RecoveredActive = $false }
    }
}
if ($eligible.Count -eq 0) { Fail "No completed or recoverable session found. Stop recording in game first (/sui reborn record stop)." }

if ($SelfTest) {
    $session = $db.sessions["selftest-001"]
    $events = @($session.events)
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
    $bigPayload = "x" * 12000
    $bigEvents = @()
    for ($i = 1; $i -le 200; $i++) {
        $bigEvents += ,@{ seq = $i; type = "synthetic"; data = @{ text = $bigPayload } }
    }
    $bigChunks = New-EventChunks $bigEvents 524288
    AssertSelfTest ($bigChunks.Count -gt 1) "payload over 1 MB must produce multiple chunks"
    $bigParsed = @()
    foreach ($chunk in $bigChunks) {
        AssertSelfTest ([System.Text.Encoding]::UTF8.GetByteCount($chunk) -le 524288) "chunk must not exceed 512 KiB"
        $decoded = ConvertFrom-Json -InputObject $chunk
        $bigParsed += @($decoded)
    }
    AssertSelfTest ($bigParsed.Count -eq 200) "all synthetic events must survive chunking"
}

function Process-DiagnosticSession($sessionId, $recoveredActive) {
    if ($sessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Session ID '$sessionId' contains unsafe characters; refusing to use it in paths." }
    $session = $db.sessions[$sessionId]
    $events = @($session.events)
    $runs = @($events | ForEach-Object { $_.run } | Where-Object { $_ } | Select-Object -Unique).Count

    $exportDir = Join-Path $ScriptDir ("export\" + $sessionId)
    New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

    $files = [ordered]@{}
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
    if ($session.dropped -is [System.Collections.IDictionary] -and $session.dropped.Count -gt 0) {
        $meta.dropped = ConvertTo-SortedValue $session.dropped
    }
    $files["metadata.json"] = $meta | ConvertTo-Json -Depth 10 -Compress
    $chunks = New-EventChunks $events 524288
    for ($i = 0; $i -lt $chunks.Count; $i++) {
        $files[("events-{0:D3}.json" -f ($i + 1))] = $chunks[$i]
    }
    $summary = "# Diagnostic session $sessionId`n`n- Status: $exportStatus`n- Original status: $($session.status)`n- Recovered active session: $([bool]$recoveredActive)`n- Addon commit: $($session.addonCommit)`n- Events: $($events.Count)`n- Runs: $runs`n- Truncated: $($session.truncated)`n"
    $files["summary.md"] = $summary

    $manifest = [ordered]@{ sessionId = $sessionId; files = [ordered]@{} }
    foreach ($name in $files.Keys) {
        $manifest.files[$name] = Sha256Hex $files[$name]
        WriteExactText (Join-Path $exportDir $name) $files[$name]
    }
    $files["manifest.json"] = $manifest | ConvertTo-Json -Depth 10 -Compress
    WriteExactText (Join-Path $exportDir "manifest.json") $files["manifest.json"]

    $base = "$BaseDir/$sessionId"
    $result = [pscustomobject]@{
        SessionId = $sessionId; Status = "uploaded"; StartedAt = $session.startedAt
        EventCount = $events.Count; RunCount = $runs; AddonCommit = $session.addonCommit; Path = $base
    }

    $remoteManifestText = GetRemoteText "$base/manifest.json"
    if ($null -ne $remoteManifestText) {
        $remoteManifest = $remoteManifestText | ConvertFrom-Json
        $remoteComplete = $true
        $remoteEvents = @()
        foreach ($name in @($remoteManifest.files.PSObject.Properties.Name | Sort-Object)) {
            $remoteText = GetRemoteText "$base/$name"
            if ($null -eq $remoteText -or (Sha256Hex $remoteText) -ne $remoteManifest.files.$name) {
                $remoteComplete = $false
                break
            }
            if ($name -like "events-*.json") {
                $decoded = ConvertFrom-Json -InputObject $remoteText
                $remoteEvents += @($decoded)
            }
        }
        if ($remoteComplete) {
            for ($i = 0; $i -lt $remoteEvents.Count; $i++) {
                if ($remoteEvents[$i].seq -ne ($i + 1)) { $remoteComplete = $false; break }
            }
        }
        if ($remoteComplete) {
            $remoteCanonical = ConvertTo-SortedValue ([object[]]@($remoteEvents)) | ConvertTo-Json -Depth 30 -Compress
            $localCanonical = ConvertTo-SortedValue ([object[]]@($events)) | ConvertTo-Json -Depth 30 -Compress
            if ($remoteCanonical -ne $localCanonical) {
                throw "Session $sessionId already exists remotely with different contents. Refusing to overwrite; investigate the collision."
            }
            $result.Status = "recovered"
            return $result
        }
        $result.Status = "recovered"
    }

    foreach ($name in $files.Keys) {
        if ($name -ne "manifest.json") { PutFile "$base/$name" $files[$name] "diagnostics: $sessionId $name" }
    }
    foreach ($name in $manifest.files.Keys) {
        $remoteText = GetRemoteText "$base/$name"
        if ($null -eq $remoteText -or (Sha256Hex $remoteText) -ne $manifest.files[$name]) {
            throw "Verification failed for $base/$name. Run the script again to retry."
        }
    }
    # Manifest last: publish it only after every data file verified.
    PutFile "$base/manifest.json" $files["manifest.json"] "diagnostics: $sessionId manifest"
    $remoteManifestCheck = GetRemoteText "$base/manifest.json"
    if ($null -eq $remoteManifestCheck -or (Sha256Hex $remoteManifestCheck) -ne (Sha256Hex $files["manifest.json"])) {
        throw "Verification failed for $base/manifest.json. Run the script again to retry."
    }
    return $result
}

$uploaded = @()
$recovered = @()
$skipped = @()
$failed = @()
$verified = @()
$existingLatest = $null
if (-not $SelfTest) {
    $existingLatestText = GetRemoteText "latest.json"
    if ($null -ne $existingLatestText) {
        try { $existingLatest = $existingLatestText | ConvertFrom-Json } catch {}
    }
}
foreach ($entry in $eligible) {
    try {
        $r = Process-DiagnosticSession $entry.Id $entry.RecoveredActive
        if ($r.Status -eq "recovered") {
            if ($existingLatest -and $existingLatest.sessionId -eq $r.SessionId) {
                $skipped += ,$r
            } else {
                $recovered += ,$r
            }
        } else {
            $uploaded += ,$r
        }
        $verified += ,$r
        Write-Host "$($r.Status): $($r.SessionId) ($($r.EventCount) events, $($r.RunCount) runs)"
    } catch {
        $failed += ,$entry.Id
        Write-Host "failed: $($entry.Id): $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $SelfTest -and $verified.Count -gt 0) {
    $newest = $verified | Sort-Object StartedAt | Select-Object -Last 1
    $updateLatest = $true
    if ($existingLatest -and $existingLatest.startedAt -and $newest.StartedAt -and [double]$existingLatest.startedAt -gt [double]$newest.StartedAt) {
        $updateLatest = $false
    }
    if ($updateLatest) {
        $latest = [ordered]@{ sessionId = $newest.SessionId; path = $newest.Path; addonCommit = $newest.AddonCommit; eventCount = $newest.EventCount; runCount = $newest.RunCount; startedAt = $newest.StartedAt }
        PutFile "latest.json" ($latest | ConvertTo-Json -Depth 10 -Compress) "diagnostics: latest $($newest.SessionId)"
    }
}

Write-Host ""
if ($SelfTest -and $failed.Count -eq 0) { Write-Host "SELF-TEST PASS" }
Write-Host "Diagnostic upload summary:"
Write-Host "Uploaded: $($uploaded.Count)"
Write-Host "Recovered: $($recovered.Count)"
Write-Host "Skipped (already verified): $($skipped.Count)"
Write-Host "Failed: $($failed.Count)"
if ($failed.Count -gt 0) {
    Write-Host "Failed sessions: $($failed -join ', ')"
    exit 1
}
Write-Host ""
Write-Host "GitHub:"
Write-Host "https://github.com/$Repo"
