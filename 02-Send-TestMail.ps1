# ====================================
# Send Test Mail
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

$Subject = "$TestSubject $(Get-Date -Format 'yyyyMMdd-HHmmss')"

if ($SendMethod -eq "Smtp")
{
    if ($SmtpMode -eq "Raw")
    {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($SmtpHost, $SmtpPort)
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true

        $SmtpStep = "connect"

        function Read-SmtpReply
        {
            $lines = New-Object System.Collections.Generic.List[string]
            do
            {
                $line = $reader.ReadLine()
                if ($null -eq $line)
                {
                    throw "SMTP connection closed unexpectedly."
                }

                $lines.Add($line)
            }
            while ($line -match "^\d{3}-")

            $reply = $lines -join "`n"
            if ($SmtpVerbose)
            {
                Write-Host "SMTP $SmtpStep : $reply"
            }

            if ($line -notmatch "^[23]\d{2}")
            {
                throw "SMTP error during ${SmtpStep}: $reply"
            }

            return $reply
        }

        try
        {
            $SmtpStep = "banner"
            Read-SmtpReply | Out-Null
            $SmtpStep = "EHLO"
            $writer.WriteLine("EHLO MailAuth.local")
            Read-SmtpReply | Out-Null

            if ($SmtpAuthUser)
            {
                if (!$SmtpAuthPassword)
                {
                    throw "SMTP auth password is not set. Set `$SmtpAuthPassword in Config.local.ps1."
                }

                $SmtpStep = "AUTH LOGIN username prompt"
                $writer.WriteLine("AUTH LOGIN")
                Read-SmtpReply | Out-Null
                $SmtpStep = "AUTH LOGIN username"
                $writer.WriteLine([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($SmtpAuthUser)))
                Read-SmtpReply | Out-Null
                $SmtpStep = "AUTH LOGIN password"
                $writer.WriteLine([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($SmtpAuthPassword)))
                Read-SmtpReply | Out-Null
            }

            $SmtpStep = "MAIL FROM"
            $writer.WriteLine("MAIL FROM:<$SenderMailbox>")
            Read-SmtpReply | Out-Null
            $SmtpStep = "RCPT TO"
            $writer.WriteLine("RCPT TO:<$ReceiverMailbox>")
            Read-SmtpReply | Out-Null
            $SmtpStep = "DATA"
            $writer.WriteLine("DATA")
            Read-SmtpReply | Out-Null

            $messageLines = @(
                "From: $SenderMailbox",
                "To: $ReceiverMailbox",
                "Subject: $Subject",
                "MIME-Version: 1.0",
                "Content-Type: text/plain; charset=us-ascii",
                "Content-Transfer-Encoding: 7bit",
                "",
                "DMARC TEST MAIL"
            )

            foreach ($line in $messageLines)
            {
                if ($line.StartsWith("."))
                {
                    $writer.WriteLine(".$line")
                }
                else
                {
                    $writer.WriteLine($line)
                }
            }

            $writer.WriteLine(".")
            $SmtpStep = "message body"
            Read-SmtpReply | Out-Null
            $writer.WriteLine("QUIT")
        }
        finally
        {
            $reader.Dispose()
            $writer.Dispose()
            $client.Dispose()
        }
    }
    else
    {
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $MailMessage.From = $SenderMailbox
        $MailMessage.To.Add($ReceiverMailbox)
        $MailMessage.Subject = $Subject
        $MailMessage.Body = "DMARC TEST MAIL"

        $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpHost, $SmtpPort)
        $SmtpClient.UseDefaultCredentials = $false
        $SmtpClient.EnableSsl = $false
        $SmtpClient.Send($MailMessage)
        $SmtpClient.Dispose()
        $MailMessage.Dispose()
    }
}
else
{
    if (!(Test-Path -LiteralPath $GraphTokenFile))
    {
        throw "Graph token not found. Run 01-Connect-M365.ps1 first."
    }

    $GraphToken = Get-Content -LiteralPath $GraphTokenFile -Encoding UTF8 | ConvertFrom-Json
    $Headers = @{
        Authorization = "Bearer $($GraphToken.access_token)"
        "Content-Type" = "application/json"
    }

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
