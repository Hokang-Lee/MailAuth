param(
    [string]$EnvelopeFrom,
    [string]$HeaderFrom,
    [string]$SenderHeader,
    [string]$Receiver,
    [string]$OriginalEml,
    [ValidateSet('Unchanged', 'Subject', 'Body')]
    [string]$Variant = 'Unchanged',
    [string]$SubjectPrefix = '[ML001] ',
    [string]$Footer = 'ML test footer: count=001',
    [string]$DeliveryHost,
    [ValidateRange(1,65535)]
    [int]$DeliveryPort = 25,
    [switch]$DeliveryNoAuth,
    [switch]$Send
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    . ./Config.ps1
    if ($DeliveryNoAuth -and !$DeliveryHost) { throw 'DeliveryNoAuth requires DeliveryHost.' }
    if ($PSBoundParameters.ContainsKey('DeliveryPort') -and !$DeliveryHost) { throw 'DeliveryPort requires DeliveryHost.' }
    if ($DeliveryHost) {
        if (!$DeliveryNoAuth) { throw 'Alternate SMTP currently requires explicit DeliveryNoAuth.' }
        $SmtpHost = $DeliveryHost
        $SmtpPort = $DeliveryPort
        # Do not forward credentials belonging to the configured SMTP server.
        $SmtpAuthUser = $null
        $SmtpAuthPassword = $null
    }
    if (!$EnvelopeFrom) { $EnvelopeFrom = $SenderMailbox }
    if (!$Receiver) { $Receiver = $GmailReceiverMailbox }
    foreach ($address in @($EnvelopeFrom, $Receiver, $HeaderFrom, $SenderHeader)) {
        if (!$address) { continue }
        if ($address -match '[\r\n<>]' -or $address -match '[^\x21-\x7e]' -or
            ([System.Net.Mail.MailAddress]::new($address)).Address -cne $address) {
            throw 'Use plain ASCII mailbox addresses without display names.'
        }
    }
    if ($SubjectPrefix -match '[\r\n]' -or $SubjectPrefix -match '[^\x20-\x7e]' -or
        $Footer -match '[^\x20-\x7e]') {
        throw 'SubjectPrefix and Footer must be single-line ASCII text.'
    }
    # Latin-1 round-trips every byte, preserving the signed MIME representation.
    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    if ($OriginalEml) {
        if ($HeaderFrom -or $SenderHeader) {
            throw 'Replay preserves original headers. Do not specify HeaderFrom or SenderHeader.'
        }
        $message = $encoding.GetString([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $OriginalEml).Path))
        if ($message -match '(?<!\r)\n|\r(?!\n)') { throw 'Original EML must use SMTP CRLF line endings.' }
        $separator = $message.IndexOf("`r`n`r`n")
        if ($separator -lt 0) { throw 'No header/body separator in EML.' }
        $headers = $message.Substring(0, $separator)
        $body = $message.Substring($separator + 4)
        if ($headers -notmatch '(?im)^DKIM-Signature:') {
            throw 'Original EML has no DKIM-Signature. Use a signed test message, not the customer inquiry.'
        }
        if ($Variant -eq 'Subject') {
            if ($headers -notmatch '(?im)^Subject:') { throw 'No Subject header to modify.' }
            $headers = [regex]::Replace($headers, '(?im)^Subject:[ \t]*', ('Subject: ' + $SubjectPrefix).Replace('$', '$$'), 1)
        }
        if ($Variant -eq 'Body') {
            if ($headers -notmatch '(?im)^Content-Type:[ \t]*text/plain(?:;|\r?$)' -or
                $headers -match '(?im)^Content-Transfer-Encoding:[ \t]*(base64|quoted-printable)') {
                throw 'Body replay requires text/plain with 7bit/8bit encoding. MIME restructuring would confound this test.'
            }
            $body = $body.TrimEnd("`r", "`n") + "`r`n`r`n$Footer`r`n"
        }
        $message = $headers + "`r`n`r`n" + $body
    } else {
        if (!$HeaderFrom) { $HeaderFrom = $EnvelopeFrom }
        if ($Variant -ne 'Unchanged') { throw 'Subject/Body variants require a signed OriginalEml.' }
        $lines = @("From: $HeaderFrom", "To: $Receiver", "Subject: ML DMARC TEST $runId")
        $lines += ('Date: ' + [DateTimeOffset]::Now.ToString('ddd, dd MMM yyyy HH:mm:ss zzz', [Globalization.CultureInfo]::InvariantCulture) -replace ':(\d{2})$', '$1')
        $lines += "Message-ID: <$runId@mailauth.invalid>"
        if ($SenderHeader) { $lines += "Sender: $SenderHeader" }
        $lines += @('MIME-Version: 1.0', 'Content-Type: text/plain; charset=us-ascii', 'Content-Transfer-Encoding: 7bit', '', 'ML DMARC TEST MAIL', '')
        $message = $lines -join "`r`n"
    }
    if (!$message.EndsWith("`r`n")) { throw 'EML must end with CRLF to preserve bytes on SMTP submission.' }
    $outputDir = Join-Path $ResultFolder "ML-Repro/$runId-$Variant"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $emlPath = Join-Path $outputDir 'message.eml'
    [System.IO.File]::WriteAllBytes([System.IO.Path]::GetFullPath($emlPath), $encoding.GetBytes($message))
    $record = [ordered]@{
        RunId = $runId; Variant = $Variant; EnvelopeFrom = $EnvelopeFrom; Receiver = $Receiver
        OriginalEml = $OriginalEml; Status = 'Prepared'; Authentication = 'NOT_CHECKED'
        SmtpHost = $SmtpHost; SmtpPort = $SmtpPort; SmtpAuthEnabled = [bool]$SmtpAuthUser
    }
    $manifest = Join-Path $outputDir 'manifest.json'
    $record | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
    Write-Host "Prepared: $emlPath"
    if (!$Send) { Write-Host 'No mail sent. Use -Send to submit this test.'; return }

    $client = [System.Net.Sockets.TcpClient]::new()
    $reader = $null; $writer = $null
    try {
        $pending = $client.BeginConnect($SmtpHost, $SmtpPort, $null, $null)
        if (!$pending.AsyncWaitHandle.WaitOne(15000)) { throw 'SMTP connect timeout.' }
        $client.EndConnect($pending)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 30000; $stream.WriteTimeout = 30000
        $reader = [System.IO.StreamReader]::new($stream, $encoding)
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        $writer.NewLine = "`r`n"; $writer.AutoFlush = $true
        function Read-Reply([int]$Expected) {
            do {
                $line = $reader.ReadLine()
                if ($null -eq $line) { throw 'SMTP connection closed.' }
                if ($line -notmatch '^\d{3}[ -]') { throw 'Malformed SMTP reply.' }
                if ([int]$line.Substring(0,3) -ne $Expected) { throw "SMTP rejected request: $line" }
            } while ($line[3] -eq '-')
        }
        Read-Reply 220
        $writer.WriteLine('EHLO MailAuth.local'); Read-Reply 250
        if ($SmtpAuthUser) {
            if (!$SmtpAuthPassword) { throw 'Configure SmtpAuthPassword in Config.local.ps1.' }
            $writer.WriteLine('AUTH LOGIN'); Read-Reply 334
            $writer.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SmtpAuthUser))); Read-Reply 334
            $writer.WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SmtpAuthPassword))); Read-Reply 235
        }
        $writer.WriteLine("MAIL FROM:<$EnvelopeFrom>"); Read-Reply 250
        $writer.WriteLine("RCPT TO:<$Receiver>"); Read-Reply 250
        $writer.WriteLine('DATA'); Read-Reply 354
        $writer.Write([regex]::Replace($message, '(?m)^\.', '..'))
        $writer.WriteLine('.'); Read-Reply 250
        $record.Status = 'SmtpAccepted'
        $record | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
        Write-Host 'SMTP accepted. Delivery and DMARC still require receiver headers.'
        $writer.WriteLine('QUIT')
    } finally {
        if ($writer) { $writer.Dispose() }
        if ($reader) { $reader.Dispose() }
        $client.Dispose()
    }
} finally { Pop-Location }
