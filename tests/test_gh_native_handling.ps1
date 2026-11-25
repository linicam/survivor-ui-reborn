# Regression test for Windows PowerShell 5.1 native-command handling.
# Run on Windows:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_gh_native_handling.ps1
#
# It loads only the helper's gh-invocation functions, runs a native
# command that writes to stderr and exits 1, and verifies that the
# exit code and stderr are captured without a terminating
# NativeCommandError. It also verifies HTTP 404 classification.
$ErrorActionPreference = "Stop"

$helper = Join-Path $PSScriptRoot "..\tools\diagnostics-helper\Upload-Diagnostics.ps1"
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) { throw "Helper parse failed: $($errors[0].Message)" }

function Fail($msg) { throw "FAIL: $msg" }
function Assert-Test($condition, $message) {
    if (-not $condition) { throw "ASSERT FAILED: $message" }
}

$wanted = @("Quote-NativeArg", "Invoke-GhNative", "GhApiResult", "GhApi", "WriteExactText")
$functions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true)
foreach ($fn in $functions) {
    if ($wanted -contains $fn.Name) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

# Native command exits 1 and writes to stderr: must be captured,
# not raised as a terminating NativeCommandError.
$script:GhPath = Join-Path $PSHOME "powershell.exe"
$result = Invoke-GhNative @("-NoProfile", "-Command", "[Console]::Error.WriteLine('gh: Not Found (HTTP 404)'); exit 1")
Assert-Test ($result.ExitCode -eq 1) "exit code 1 must be captured"
Assert-Test ($result.StdErr -match "HTTP 404") "stderr must be captured"

# HTTP 404 from gh api is an expected missing-file result.
function Invoke-GhNative($arguments) {
    return [pscustomobject]@{
        ExitCode = 1
        StdOut = ""
        StdErr = "gh: Not Found (HTTP 404)"
    }
}
$notFound = GhApiResult "GET" "repos/example/repo/contents/missing.json" $null
Assert-Test (-not $notFound.Ok) "404 result must not be Ok"
Assert-Test ($notFound.IsNotFound) "404 result must be classified as not found"
Assert-Test ($null -eq (GhApi "GET" "repos/example/repo/contents/missing.json" $null)) "GhApi must return null for 404"

# Non-404 API failures remain actionable errors.
function Invoke-GhNative($arguments) {
    return [pscustomobject]@{
        ExitCode = 1
        StdOut = ""
        StdErr = "gh: Bad credentials (HTTP 401)"
    }
}
$threw = $false
try {
    GhApi "GET" "repos/example/repo" $null | Out-Null
} catch {
    $threw = $_.Exception.Message -match "HTTP 401"
}
Assert-Test $threw "401 must fail with the gh error detail"

Write-Host "PASS: native gh handling regression test"
