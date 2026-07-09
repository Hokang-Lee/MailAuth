# ====================================
# Connect Microsoft Graph
# ====================================

. .\Config.ps1

if (!(Test-Path $ResultFolder))
{
    New-Item `
      -ItemType Directory `
      -Path $ResultFolder | Out-Null
}

function Save-GraphToken($Token)
{
    $expiresAt = (Get-Date).AddSeconds([int]$Token.expires_in - 300).ToString("o")
    [PSCustomObject]@{
        tenant_id = $TenantId
        client_id = $ClientId
        access_token = $Token.access_token
        refresh_token = $Token.refresh_token
        expires_at = $expiresAt
    } | ConvertTo-Json | Set-Content -LiteralPath $GraphTokenFile -Encoding UTF8
}

function Request-TokenByRefresh($RefreshToken)
{
    Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method POST `
        -Body @{
            client_id = $ClientId
            grant_type = "refresh_token"
            refresh_token = $RefreshToken
            scope = $GraphScopes
        } `
        -TimeoutSec 30
}

if (Test-Path -LiteralPath $GraphTokenFile)
{
    $savedToken = Get-Content -LiteralPath $GraphTokenFile -Encoding UTF8 | ConvertFrom-Json

    if (
        $savedToken.tenant_id -eq $TenantId -and
        $savedToken.client_id -eq $ClientId -and
        [datetime]$savedToken.expires_at -gt (Get-Date)
    )
    {
        Write-Host ""
        Write-Host "Graph Token Reused"
        Write-Host "Tenant  : $TenantId"
        Write-Host "Client  : $ClientId"
        Write-Host ""
        return
    }

    if ($savedToken.refresh_token)
    {
        try
        {
            $token = Request-TokenByRefresh $savedToken.refresh_token
            Save-GraphToken $token

            Write-Host ""
            Write-Host "Graph Token Refreshed"
            Write-Host "Tenant  : $TenantId"
            Write-Host "Client  : $ClientId"
            Write-Host ""
            return
        }
        catch
        {
            Write-Host "Refresh token failed. Starting device code flow..."
        }
    }
}

$device = Invoke-RestMethod `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
    -Method POST `
    -Body @{
        client_id = $ClientId
        scope = $GraphScopes
    } `
    -TimeoutSec 30

Write-Host ""
Write-Host "Graph Device Code Authentication"
Write-Host "URL  : $($device.verification_uri)"
Write-Host "Code : $($device.user_code)"
Write-Host ""

Start-Process $device.verification_uri

$body = @{
    grant_type = "urn:ietf:params:oauth:grant-type:device_code"
    client_id = $ClientId
    device_code = $device.device_code
}

$deadline = (Get-Date).AddSeconds([int]$device.expires_in)
$token = $null

while ((Get-Date) -lt $deadline)
{
    Start-Sleep -Seconds ([int]$device.interval)

    try
    {
        $token = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST `
            -Body $body `
            -TimeoutSec 30
        break
    }
    catch
    {
        $errorText = $_.ErrorDetails.Message

        if ($errorText -match "authorization_pending")
        {
            continue
        }

        if ($errorText -match "slow_down")
        {
            Start-Sleep -Seconds 5
            continue
        }

        throw
    }
}

if (!$token)
{
    throw "Graph device code authentication timed out."
}

Save-GraphToken $token

Write-Host ""
Write-Host "Graph Connected"
Write-Host "Tenant  : $TenantId"
Write-Host "Client  : $ClientId"
Write-Host ""
