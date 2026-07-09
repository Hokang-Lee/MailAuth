# ====================================
# Send Test Mail
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

if (!(Test-Path -LiteralPath $GraphTokenFile))
{
    throw "Graph token not found. Run 01-Connect-M365.ps1 first."
}

$GraphToken = Get-Content -LiteralPath $GraphTokenFile -Encoding UTF8 | ConvertFrom-Json
$Headers = @{
    Authorization = "Bearer $($GraphToken.access_token)"
    "Content-Type" = "application/json"
}

$Subject = "$TestSubject $(Get-Date -Format 'yyyyMMdd-HHmmss')"

if ($SendMethod -eq "Smtp")
{
    $MailMessage = New-Object System.Net.Mail.MailMessage
    $MailMessage.From = $SenderMailbox
    $MailMessage.To.Add($ReceiverMailbox)
    $MailMessage.Subject = $Subject
    $MailMessage.Body = "DMARC TEST MAIL"

    $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpHost, $SmtpPort)
    $SmtpClient.Send($MailMessage)
    $SmtpClient.Dispose()
    $MailMessage.Dispose()
}
else
{
    $Body = @{
        message = @{
            subject = $Subject
            body = @{
                contentType = "Text"
                content = "DMARC TEST MAIL"
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $ReceiverMailbox
                    }
                }
            )
        }
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 10

    if ($GraphSenderUser -eq "me")
    {
        $SendMailUri = "https://graph.microsoft.com/v1.0/me/sendMail"
    }
    else
    {
        $EncodedSender = [System.Uri]::EscapeDataString($GraphSenderUser)
        $SendMailUri = "https://graph.microsoft.com/v1.0/users/$EncodedSender/sendMail"
    }

    Invoke-RestMethod `
        -Uri $SendMailUri `
        -Method POST `
        -Headers $Headers `
        -Body $Body `
        -TimeoutSec 30 | Out-Null
}

Write-Host ""
Write-Host "Mail Sent"
Write-Host "Method  : $SendMethod"
Write-Host "Subject : $Subject"
Write-Host "From    : $SenderMailbox"
Write-Host "To      : $ReceiverMailbox"
Write-Host ""

$Subject | Out-File .\last_subject.txt -Encoding UTF8
