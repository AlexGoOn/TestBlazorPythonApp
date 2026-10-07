$ErrorActionPreference = 'Stop'
$fixture = @{
    Environment = @{
        AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
        AZURE_RESOURCE_GROUP = 'rg-template-dev'
        AZURE_BACKEND_NAME = 'app-template-python-test-dev'
        AZURE_FRONTEND_NAME = 'app-template-test-dev'
    }
    Paths = @()
    Content = (1..210 | ForEach-Object { "Startup line $_" }) -join "`n"
    FailRequest = $false
    Service = 'backend'
}

function azd {
    if (($args -join ' ') -ne 'env get-values --output json') { throw 'Unexpected azd command.' }
    $global:LASTEXITCODE = 0
    return ($fixture.Environment | ConvertTo-Json)
}

function az {
    $global:LASTEXITCODE = 0
    if ((($args | Select-Object -First 2) -join ' ') -eq 'account show') {
        return (@{
            id = $fixture.Environment.AZURE_SUBSCRIPTION_ID
            tenantId = $fixture.Environment.AZURE_TENANT_ID
        } | ConvertTo-Json)
    }
    if ($args[0] -ne 'rest') { throw 'Unexpected Azure CLI command.' }
    $name = if ($fixture.Service -eq 'backend') {
        $fixture.Environment.AZURE_BACKEND_NAME
    } else {
        $fixture.Environment.AZURE_FRONTEND_NAME
    }
    $expectedUri = "https://management.azure.com/subscriptions/$($fixture.Environment.AZURE_SUBSCRIPTION_ID)/resourceGroups/rg-template-dev/providers/Microsoft.Web/sites/$name/containerlogs?api-version=2024-04-01"
    if ($args[[array]::IndexOf($args, '--method') + 1] -ne 'post' -or
        $args[[array]::IndexOf($args, '--url') + 1] -cne $expectedUri) {
        throw 'The diagnostic script did not use the documented management API.'
    }
    $path = $args[[array]::IndexOf($args, '--output-file') + 1]
    $fixture.Paths += $path
    if ($fixture.FailRequest) {
        $global:LASTEXITCODE = 1
        return
    }
    [System.IO.File]::WriteAllText($path, $fixture.Content)
}

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra\hooks\runtime-logs.ps1'
foreach ($service in @('backend', 'frontend')) {
    $fixture.Service = $service
    $output = @(& $scriptPath -Service $service)
    if ($output.Count -ne 200 -or $output[0] -ne 'Startup line 11' -or $output[-1] -ne 'Startup line 210') {
        throw "The script did not return the last 200 lines for $service."
    }
}
$fixture.Content = ''
$output = @(& $scriptPath -Service frontend)
if ($output.Count -ne 0) { throw 'Empty logs must not be presented as successful runtime output.' }
$fixture.FailRequest = $true
$rejected = $false
try { & $scriptPath -Service frontend } catch {
    if ($_.Exception.Message -notmatch 'Cannot retrieve startup logs') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'A failed logs request was not surfaced.' }
foreach ($path in $fixture.Paths) {
    if (Test-Path -LiteralPath $path) { throw "Temporary log file was not removed: $path" }
}
Write-Host 'Runtime log tests passed without Azure: both apps, API method/path, bounded output, empty/error responses and cleanup.'
