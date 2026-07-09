# ====================================
# Connect Gmail API
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

if (!(Test-Path $ResultFolder))
{
    New-Item -ItemType Directory -Path $ResultFolder | Out-Null
}

if (!(Test-Path -LiteralPath $GmailClientSecretFile))
{
    throw "Gmail OAuth client secret not found: $GmailClientSecretFile"
}

$clientConfig = Get-Content -LiteralPath $GmailClientSecretFile -Encoding UTF8 | ConvertFrom-Json
$client = if ($clientConfig.installed) { $clientConfig.installed } else { $clientConfig.web }
$clientType = if ($clientConfig.installed) { "installed" } else { "web" }

if (!$client -or !$client.client_id -or !$client.client_secret)
{
    throw "Invalid Gmail OAuth client secret JSON. Create an OAuth client for a Desktop app."
}

function Save-GmailToken($Token)
{
    $expiresAt = (Get-Date).AddSeconds([int]$Token.expires_in - 300).ToString("o")
    [PSCustomObject]@{
        client_id = $client.client_id
        access_token = $Token.access_token
        refresh_token = if ($Token.refresh_token) { $Token.refresh_token } else { $script:savedRefreshToken }
        expires_at = $expiresAt
        scope = $Token.scope
        token_type = $Token.token_type
    } | ConvertTo-Json | Set-Content -LiteralPath $GmailTokenFile -Encoding UTF8
}

function Request-GmailTokenByRefresh($RefreshToken)
{
    Invoke-RestMethod `
        -Uri $client.token_uri `
        -Method POST `
        -Body @{
            client_id = $client.client_id
            client_secret = $client.client_secret
            refresh_token = $RefreshToken
            grant_type = "refresh_token"
        } `
        -TimeoutSec 30
}

if (Test-Path -LiteralPath $GmailTokenFile)
{
    $savedToken = Get-Content -LiteralPath $GmailTokenFile -Encoding UTF8 | ConvertFrom-Json
    $script:savedRefreshToken = $savedToken.refresh_token

    if (
        $savedToken.client_id -eq $client.client_id -and
        [datetime]$savedToken.expires_at -gt (Get-Date)
    )
    {
        Write-Host ""
        Write-Host "Gmail Token Reused"
        Write-Host "Account : $GmailSenderMailbox"
        Write-Host ""
        return
    }

    if ($savedToken.refresh_token)
    {
        try
        {
            $token = Request-GmailTokenByRefresh $savedToken.refresh_token
            Save-GmailToken $token

            Write-Host ""
            Write-Host "Gmail Token Refreshed"
            Write-Host "Account : $GmailSenderMailbox"
            Write-Host ""
            return
        }
        catch
        {
            Write-Host "Refresh token failed. Starting browser OAuth flow..."
        }
    }
}

$redirectUri = "http://127.0.0.1:$GmailRedirectPort/"

if ($clientType -eq "installed" -and @($client.redirect_uris) -contains "http://localhost")
{
    $redirectUri = "http://localhost:$GmailRedirectPort/"
}

if ($clientType -eq "web" -and @($client.redirect_uris) -notcontains $redirectUri)
{
    throw "Gmail OAuth client is web type and does not allow redirect URI $redirectUri. Add that URI in Google Cloud, or replace the file with a Desktop app OAuth client JSON."
}

$encodedRedirect = [System.Uri]::EscapeDataString($redirectUri)
$encodedScope = [System.Uri]::EscapeDataString($GmailScopes)
$state = [guid]::NewGuid().ToString("N")
$authUri = "$($client.auth_uri)?client_id=$($client.client_id)&redirect_uri=$encodedRedirect&response_type=code&scope=$encodedScope&access_type=offline&prompt=consent&state=$state"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($redirectUri)
$listener.Start()

Write-Host ""
Write-Host "Gmail OAuth Authentication"
Write-Host "URL : $authUri"
Write-Host ""

Start-Process $authUri

$context = $listener.GetContext()
$request = $context.Request
$response = $context.Response

$html = "<html><body>Gmail authentication completed. You can close this window.</body></html>"
$buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
$response.ContentLength64 = $buffer.Length
$response.OutputStream.Write($buffer, 0, $buffer.Length)
$response.OutputStream.Close()
$listener.Stop()

$code = $request.QueryString["code"]
$returnedState = $request.QueryString["state"]
$errorCode = $request.QueryString["error"]

if ($errorCode)
{
    throw "Gmail OAuth failed: $errorCode"
}

if (!$code -or $returnedState -ne $state)
{
    throw "Gmail OAuth response was invalid."
}

$token = Invoke-RestMethod `
    -Uri $client.token_uri `
    -Method POST `
    -Body @{
        code = $code
        client_id = $client.client_id
        client_secret = $client.client_secret
        redirect_uri = $redirectUri
        grant_type = "authorization_code"
    } `
    -TimeoutSec 30

Save-GmailToken $token

Write-Host ""
Write-Host "Gmail Connected"
Write-Host "Account : $GmailSenderMailbox"
Write-Host ""
