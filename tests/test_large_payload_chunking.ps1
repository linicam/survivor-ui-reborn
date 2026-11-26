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

$wanted = @("ConvertTo-SortedValue", "New-EventChunks")
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
    $parsed += @($chunk | ConvertFrom-Json)
}
Assert-Test ($parsed.Count -eq 200) "all events must survive chunking"
for ($i = 0; $i -lt $parsed.Count; $i++) {
    Assert-Test ($parsed[$i].seq -eq ($i + 1)) "event sequence must remain continuous"
}

Write-Host "PASS: large payload chunking regression test"
