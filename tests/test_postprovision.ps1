$ErrorActionPreference = 'Stop'
$fixture = @{
    Environment = @{
        AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
        AZURE_RESOURCE_GROUP = 'rg-template-dev'
        AZURE_FRONTEND_NAME = 'app-template-test-dev'
        ENTRA_CLIENT_ID = '33333333-3333-3333-3333-333333333333'
        ENTRA_CALLBACK_URL = 'https://test.example/.auth/login/aad/callback'
    }
    Statuses = @('Resolved')
    Requests = 0
    Sleeps = 0
    FailRequest = $false
}
$expectedUri = 'https://management.azure.com/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-template-dev/providers/Microsoft.Web/sites/app-template-test-dev/config/configreferences/appsettings/MICROSOFT_PROVIDER_AUTHENTICATION_SECRET?api-version=2024-04-01'

function azd {
    if (($args -join ' ') -ne 'env get-values --output json') {
        throw 'Unexpected azd command in postprovision test.'
    }
    $global:LASTEXITCODE = 0
    return ($fixture.Environment | ConvertTo-Json)
}

function az {
    $global:LASTEXITCODE = 0
    if (($args | Select-Object -First 2) -join ' ' -eq 'account show') {
        return (@{
            id = $fixture.Environment.AZURE_SUBSCRIPTION_ID
            tenantId = $fixture.Environment.AZURE_TENANT_ID
        } | ConvertTo-Json)
    }
    if ($args[0] -ne 'rest') { throw 'Unexpected Azure CLI command in postprovision test.' }
    $method = $args[[array]::IndexOf($args, '--method') + 1]
    $uri = $args[[array]::IndexOf($args, '--url') + 1]
    if ($method -ne 'get' -or $uri -cne $expectedUri) {
        throw 'The hook did not use the documented GET endpoint for a single Key Vault reference.'
    }
    $fixture.Requests++
    if ($fixture.FailRequest) {
        $global:LASTEXITCODE = 1
        return 'API request failed.'
    }
    $index = [Math]::Min($fixture.Requests - 1, $fixture.Statuses.Count - 1)
    return (@{ properties = @{ status = $fixture.Statuses[$index] } } | ConvertTo-Json)
}

function Start-Sleep {
    param([int] $Seconds)
    if ($Seconds -ne 10) { throw 'Unexpected retry delay.' }
    $fixture.Sleeps++
}

$hook = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra\hooks\postprovision.ps1'
& $hook
if ($fixture.Requests -ne 1 -or $fixture.Sleeps -ne 0) {
    throw 'Resolved references should succeed without retries.'
}
$fixture.Statuses = @('Initializing', 'Resolved')
$fixture.Requests = 0
& $hook
if ($fixture.Requests -ne 2 -or $fixture.Sleeps -ne 1) {
    throw 'The hook must retry references that have not resolved yet.'
}

foreach ($case in @(
    @{ Status = 'AccessToKeyVaultDenied'; Error = 'status: AccessToKeyVaultDenied'; Requests = 12; Sleeps = 11; Fail = $false },
    @{ Status = ''; Error = 'did not return a resolution status'; Requests = 1; Sleeps = 0; Fail = $false },
    @{ Status = 'Resolved'; Error = 'Azure CLI failed'; Requests = 1; Sleeps = 0; Fail = $true }
)) {
    $fixture.Statuses = @($case.Status)
    $fixture.Requests = 0
    $fixture.Sleeps = 0
    $fixture.FailRequest = $case.Fail
    $rejected = $false
    try { & $hook } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($case.Error)) { throw }
        $rejected = $true
    }
    if (-not $rejected -or $fixture.Requests -ne $case.Requests -or $fixture.Sleeps -ne $case.Sleeps) {
        throw "The hook did not handle the error case correctly: $($case.Error)"
    }
}
Write-Host 'Postprovision tests passed without Azure: GET URL, single-reference response, retries and explicit failures.'
