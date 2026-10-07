param(
    [Parameter(Mandatory)]
    [guid] $SubscriptionId,
    [string] $RoleName = 'TestBlazorPythonApp Subnet Join'
)

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'infra\hooks\common.ps1')
$account = Invoke-AzureJson -Arguments @('account', 'show')
if ($account.id -ne $SubscriptionId.ToString()) {
    throw 'Select the intended subscription with az account set before updating its custom role.'
}
$roles = @(Invoke-AzureJson -Arguments @(
    'role', 'definition', 'list', '--name', $RoleName, '--subscription', $SubscriptionId.ToString()
))
if ($roles.Count -ne 1 -or $roles[0].roleType -ne 'CustomRole') {
    throw "Expected exactly one existing custom role named '$RoleName'."
}
$role = $roles[0]
if (-not @($role.assignableScopes | Where-Object {
    $_ -eq "/subscriptions/$SubscriptionId" -or $_ -like "/subscriptions/$SubscriptionId/*"
}).Count) {
    throw 'The custom role must have an assignable scope in the selected subscription.'
}
$requiredActions = @(
    'Microsoft.Network/virtualNetworks/subnets/join/action',
    'Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action'
)
if (-not $role.permissions.Count) { throw 'The custom role has no permissions block.' }
foreach ($permission in $role.permissions) {
    foreach ($excluded in $permission.notActions) {
        if (@($requiredActions | Where-Object { $_ -like $excluded }).Count) {
            throw 'The role excludes a required subnet action. Review NotActions before updating it.'
        }
    }
}
$role.permissions[0].actions = @(
    @($role.permissions[0].actions) + $requiredActions | Sort-Object -Unique
)

$path = [System.IO.Path]::GetTempFileName()
try {
    $role | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
    $null = Invoke-AzureJson -Arguments @(
        'role', 'definition', 'update', '--role-definition', $path,
        '--subscription', $SubscriptionId.ToString()
    )
} finally {
    Remove-Item -LiteralPath $path
}
Write-Host "Updated '$RoleName' with both subnet actions. Existing role assignments and scopes are unchanged."
