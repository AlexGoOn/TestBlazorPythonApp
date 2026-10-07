. (Join-Path $PSScriptRoot 'common.ps1')
Import-AzdEnvironment

if ([string]::IsNullOrWhiteSpace($env:ENTRA_AUTHORITY_URL)) {
    throw 'ENTRA_AUTHORITY_URL is missing. Run azd provision with the current template before deploying frontend.'
}
$frontendUri = [Uri] "$env:APP_WEB_URL/"
$allowedLoginTargets = @(
    "$($frontendUri.GetLeftPart([UriPartial]::Authority))/.auth/login/aad",
    "$($env:ENTRA_AUTHORITY_URL.TrimEnd('/'))/oauth2/v2.0/authorize"
)

$client = [System.Net.Http.HttpClient]::new(
    [System.Net.Http.HttpClientHandler] @{ AllowAutoRedirect = $false }
)
$client.Timeout = [TimeSpan]::FromSeconds(30)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0')
$client.DefaultRequestHeaders.Accept.ParseAdd('text/html')
try {
    foreach ($probe in @(
        @{ Url = "$env:APP_WEB_URL/"; Status = 302 },
        @{ Url = "$env:APP_API_URL/notes"; Status = 403 }
    )) {
        Write-Host "Checking anonymous access: $($probe.Url) (expected $($probe.Status))."
        try {
            $response = $client.GetAsync($probe.Url).GetAwaiter().GetResult()
        } catch [System.Management.Automation.MethodInvocationException] {
            throw "Cloud access check could not reach '$($probe.Url)': $($_.Exception.Message). Check this Web App's startup logs; the request did not produce an HTTP status."
        }
        try {
            if ([int] $response.StatusCode -ne $probe.Status) {
                throw "Cloud access check failed for $($probe.Url): expected $($probe.Status), got $([int] $response.StatusCode)."
            }
            if ($probe.Status -eq 302) {
                if ($null -eq $response.Headers.Location) {
                    throw 'Blazor did not redirect to Easy Auth: missing Location header.'
                }
                $loginUri = [Uri]::new($frontendUri, $response.Headers.Location)
                if ($loginUri.GetLeftPart([UriPartial]::Path) -notin $allowedLoginTargets) {
                    throw 'Blazor did not redirect to Easy Auth or the configured Entra tenant.'
                }
            }
        } finally {
            $response.Dispose()
        }
    }
} finally {
    $client.Dispose()
}
Write-Host 'Anonymous Blazor access requires login; public Python access is denied. Run the authenticated Azure browser test to verify both SQL writers.'
