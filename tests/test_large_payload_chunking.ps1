# Regression test for byte-size event chunking with payloads over 1 MB.
# Run on Windows:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_large_payload_chunking.ps1
$ErrorActionPreference = "Stop"

$helper = Join-Path $PSScriptRoot "..\tools\diagnostics-helper\Upload-Diagnostics.ps1"
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) { throw "Helper parse failed: $($errors[0].Message)" }

function Assert-Test($condition, $message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
}

$wanted = @("ConvertTo-SortedValue", "New-EventChunks", "Process-DiagnosticSession", "WriteExactText", "Sha256Hex")
$functions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true)
foreach ($fn in $functions) {
    if ($wanted -contains $fn.Name) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

$payload = "x" * 12000
$events = @()
for ($i = 1; $i -le 200; $i++) {
    $events += ,@{ seq = $i; type = "synthetic"; data = @{ text = $payload } }
}
$totalBytes = [System.Text.Encoding]::UTF8.GetByteCount((ConvertTo-SortedValue ([object[]]@($events)) | ConvertTo-Json -Depth 30 -Compress))
Assert-Test ($totalBytes -gt 1048576) "synthetic payload must exceed 1 MB"

$chunks = New-EventChunks $events 524288
Assert-Test ($chunks.Count -gt 1) "payload over 1 MB must produce multiple chunks"
$parsed = @()
foreach ($chunk in $chunks) {
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($chunk)
    Assert-Test ($bytes -le 524288) "chunk must not exceed 512 KiB (got $bytes)"
    # Windows PowerShell writes a decoded JSON array as one pipeline object.
    $chunkEvents = ConvertFrom-Json -InputObject $chunk
    $parsed += @($chunkEvents)
}
Assert-Test ($parsed.Count -eq 200) "all events must survive chunking"
for ($i = 0; $i -lt $parsed.Count; $i++) {
    Assert-Test ($parsed[$i].seq -eq ($i + 1)) "event sequence must remain continuous"
}

Write-Host "PASS: large payload chunking regression test"

# Exercise manifest creation and duplicate verification without network access.
$testRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$ScriptDir = Join-Path $testRoot ("sui-diagnostics-" + [guid]::NewGuid().ToString("N"))
$BaseDir = "test"
$script:remoteFiles = @{}
function GetRemoteText($path) { return $script:remoteFiles[$path] }
function PutFile($path, $content, $message) { $script:remoteFiles[$path] = $content }
$db = @{ sessions = @{
    "truncated-fixture" = @{ status = "completed"; truncated = $true; events = $events; dropped = @{ tooltip = 2; guardian_lairs = 7 } }
    "legacy-fixture" = @{ status = "completed"; events = @($events[0]) }
} }
try {
    $result = Process-DiagnosticSession "truncated-fixture" $false
    Assert-Test ($result.Status -eq "uploaded") "synthetic export should verify"
    $base = "test/truncated-fixture"
    $metadata = $script:remoteFiles["$base/metadata.json"] | ConvertFrom-Json
    $manifest = $script:remoteFiles["$base/manifest.json"] | ConvertFrom-Json
    Assert-Test ($metadata.dropped.tooltip -eq 2 -and $metadata.dropped.guardian_lairs -eq 7) "drop counters should survive export"
    Assert-Test ($manifest.files.'metadata.json' -eq (Sha256Hex $script:remoteFiles["$base/metadata.json"])) "manifest should hash new metadata"
    $result = Process-DiagnosticSession "truncated-fixture" $false
    Assert-Test ($result.Status -eq "recovered") "multiple remote JSON arrays should verify on retry"
    $null = Process-DiagnosticSession "legacy-fixture" $false
    $legacyMetadata = $script:remoteFiles["test/legacy-fixture/metadata.json"] | ConvertFrom-Json
    Assert-Test (-not $legacyMetadata.PSObject.Properties["dropped"]) "legacy sessions may omit drop counts"
    Write-Host "PASS: diagnostic metadata and manifest regression test"
} finally {
    if (Test-Path -LiteralPath $ScriptDir) {
        $resolved = (Resolve-Path -LiteralPath $ScriptDir).ProviderPath
        if ([IO.Path]::GetDirectoryName($resolved) -eq $testRoot.TrimEnd('\')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
