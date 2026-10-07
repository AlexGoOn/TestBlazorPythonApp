. (Join-Path $PSScriptRoot 'common.ps1')
Import-AzdEnvironment

$client = [System.Net.Http.HttpClient]::new(
    [System.Net.Http.HttpClientHandler] @{ AllowAutoRedirect = $false }
)
$client.Timeout = [TimeSpan]::FromSeconds(30)
try {
    foreach ($probe in @(
        @{ Url = "$env:APP_WEB_URL/"; Status = 302 },
        @{ Url = "$env:APP_API_URL/notes"; Status = 403 }
    )) {
        $response = $client.GetAsync($probe.Url).GetAwaiter().GetResult()
        try {
            if ([int] $response.StatusCode -ne $probe.Status) {
                throw "Cloud access check failed for $($probe.Url): expected $($probe.Status), got $([int] $response.StatusCode)."
            }
            if ($probe.Status -eq 302 -and
                $response.Headers.Location.OriginalString -notmatch '/\.auth/login/aad') {
                throw 'Blazor did not redirect to Easy Auth.'
            }
        } finally {
            $response.Dispose()
        }
    }
} finally {
    $client.Dispose()
}
Write-Host 'Anonymous Blazor access requires login; public Python access is denied. Run the authenticated Azure browser test to verify both SQL writers.'
