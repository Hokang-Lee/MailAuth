# ====================================
# Send Gmail Test Mail
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

if (!(Test-Path -LiteralPath $GmailTokenFile))
{
    throw "Gmail token not found. Run 05-Connect-Gmail.ps1 first."
}

$GmailToken = Get-Content -LiteralPath $GmailTokenFile -Encoding UTF8 | ConvertFrom-Json
$Headers = @{
    Authorization = "Bearer $($GmailToken.access_token)"
    "Content-Type" = "application/json"
}

$Subject = "$TestSubject GMAIL $(Get-Date -Format 'yyyyMMdd-HHmmss')"

$rawMessage = @"
From: <$GmailSenderMailbox>
To: <$GmailReceiverMailbox>
Subject: $Subject
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

GMAIL DMARC TEST MAIL
"@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($rawMessage)
$raw = [Convert]::ToBase64String($bytes).TrimEnd("=") -replace "\+", "-" -replace "/", "_"
$body = @{ raw = $raw } | ConvertTo-Json

Invoke-RestMethod `
    -Uri "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" `
    -Method POST `
    -Headers $Headers `
    -Body $body `
    -TimeoutSec 30 | Out-Null

Write-Host ""
Write-Host "Gmail Mail Sent"
Write-Host "Subject : $Subject"
Write-Host "From    : $GmailSenderMailbox"
Write-Host "To      : $GmailReceiverMailbox"
Write-Host ""

$Subject | Out-File .\last_subject.txt -Encoding UTF8
