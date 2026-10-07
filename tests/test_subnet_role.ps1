$ErrorActionPreference = 'Stop'
$subscriptionId = '11111111-1111-1111-1111-111111111111'
$fixture = @{
    AccountId = $subscriptionId
    Updates = @()
    Role = @{
        id = "/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
        name = '22222222-2222-2222-2222-222222222222'
        roleName = 'TestBlazorPythonApp Subnet Join'
        roleType = 'CustomRole'
        assignableScopes = @("/subscriptions/$subscriptionId/resourceGroups/rg-shared")
        permissions = @(@{
            actions = @('Microsoft.Network/virtualNetworks/subnets/join/action', 'Microsoft.Network/virtualNetworks/subnets/read')
            notActions = @()
            dataActions = @()
            notDataActions = @()
        })
    }
}

function az {
    $global:LASTEXITCODE = 0
    $command = ($args | Select-Object -First 3) -join ' '
    if ($args[0] -eq 'account') {
        return (@{ id = $fixture.AccountId } | ConvertTo-Json)
    }
    if ($command -eq 'role definition list') {
        return (ConvertTo-Json -InputObject @($fixture.Role) -Depth 20)
    }
    if ($command -eq 'role definition update') {
        $index = [array]::IndexOf($args, '--role-definition') + 1
        $updated = Get-Content -LiteralPath $args[$index] -Raw | ConvertFrom-Json
        $fixture.Updates += $updated
        return ($updated | ConvertTo-Json -Depth 20)
    }
    throw "Unexpected Azure CLI command in test: $command"
}

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\update-subnet-deploy-role.ps1'
& $scriptPath -SubscriptionId $subscriptionId
$fixture.Role = $fixture.Updates[0]
& $scriptPath -SubscriptionId $subscriptionId
foreach ($updated in $fixture.Updates) {
    foreach ($action in @(
        'Microsoft.Network/virtualNetworks/subnets/join/action',
        'Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action',
        'Microsoft.Network/virtualNetworks/subnets/read'
    )) {
        if (@($updated.permissions[0].actions | Where-Object { $_ -eq $action }).Count -ne 1) {
            throw "Required/existing action was lost or duplicated: $action"
        }
    }
    if ($updated.id -ne $fixture.Role.id -or
        ($updated.assignableScopes -join ',') -ne ($fixture.Role.assignableScopes -join ',')) {
        throw 'The updater changed the role ID or assignable scopes.'
    }
}
if ($fixture.Updates.Count -ne 2) { throw 'The role update was not executed.' }

$fixture.AccountId = '33333333-3333-3333-3333-333333333333'
$rejected = $false
try { & $scriptPath -SubscriptionId $subscriptionId } catch {
    if ($_.Exception.Message -notmatch 'Select the intended subscription') { throw }
    $rejected = $true
}
if (-not $rejected -or $fixture.Updates.Count -ne 2) {
    throw 'The updater did not reject the wrong Azure subscription.'
}
$fixture.AccountId = $subscriptionId
$fixture.Role.permissions[0].notActions = @('Microsoft.Network/*')
$rejected = $false
try { & $scriptPath -SubscriptionId $subscriptionId } catch {
    if ($_.Exception.Message -notmatch 'role excludes a required') { throw }
    $rejected = $true
}
if (-not $rejected -or $fixture.Updates.Count -ne 2) {
    throw 'The updater did not reject exclusions of required actions.'
}
Write-Host 'Subnet role tests passed without calling Azure: both actions, preserved permissions/scopes/ID, repeatability and invalid-context rejection.'
