# ====================================
# Gmail DMARC Check
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

if (!(Test-Path -LiteralPath $GmailTokenFile))
{
    throw "Gmail token not found. Run 05-Connect-Gmail.ps1 first."
}

function ConvertFrom-Base64Url($Value)
{
    $base64 = $Value.Replace("-", "+").Replace("_", "/")
    switch ($base64.Length % 4)
    {
        2 { $base64 += "==" }
        3 { $base64 += "=" }
    }

    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
}

function Get-HeaderValuesFromRawMessage($RawMessage, $HeaderName)
{
    $normalized = $RawMessage -replace "`r`n", "`n"
    $headerEnd = $normalized.IndexOf("`n`n")

    if ($headerEnd -lt 0)
    {
        return @()
    }

    $headerText = $normalized.Substring(0, $headerEnd)
    $logicalLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in ($headerText -split "`n"))
    {
        if ($line -match "^[ `t]" -and $logicalLines.Count -gt 0)
        {
            $logicalLines[$logicalLines.Count - 1] = $logicalLines[$logicalLines.Count - 1] + " " + $line.Trim()
        }
        else
        {
            $logicalLines.Add($line)
        }
    }

    @(
        foreach ($line in $logicalLines)
        {
            if ($line -match "^([^:]+):\s*(.*)$" -and $matches[1] -ieq $HeaderName)
            {
                $matches[2]
            }
        }
    )
}

function Get-AuthenticationResultValue($Header, $Name)
{
    if ($Header -match "(?i)(^|[;`r`n])\s*$Name=([a-z0-9_-]+)")
    {
        return $matches[2].ToUpperInvariant()
    }

    return "NOT_FOUND"
}

if (!(Test-Path $ResultFolder))
{
    New-Item -ItemType Directory -Path $ResultFolder | Out-Null
}

$GmailToken = Get-Content -LiteralPath $GmailTokenFile -Encoding UTF8 | ConvertFrom-Json
$Headers = @{
    Authorization = "Bearer $($GmailToken.access_token)"
}

$Subject = (Get-Content .\last_subject.txt -Encoding UTF8 | Select-Object -First 1)
$query = [System.Uri]::EscapeDataString("to:$GmailReceiverMailbox subject:`"$Subject`" newer_than:1d")
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$message = $null

do
{
    $list = Invoke-RestMethod `
        -Uri "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=$query&maxResults=1&includeSpamTrash=true" `
        -Method GET `
        -Headers $Headers `
        -TimeoutSec 30

    $message = $list.messages | Select-Object -First 1

    if (!$message)
    {
        Start-Sleep -Seconds 5
    }
}
while (!$message -and (Get-Date) -lt $deadline)

if (!$message)
{
    Write-Host ""
    Write-Host "Gmail mail not found"
    Write-Host ""
    exit
}

$rawResponse = Invoke-RestMethod `
    -Uri "https://gmail.googleapis.com/gmail/v1/users/me/messages/$($message.id)?format=raw" `
    -Method GET `
    -Headers $Headers `
    -TimeoutSec 30

$rawMessage = ConvertFrom-Base64Url $rawResponse.raw
$Header = (Get-HeaderValuesFromRawMessage $rawMessage "Authentication-Results") -join "`n"
$HeaderSource = if ([string]::IsNullOrWhiteSpace($Header)) { "not_found" } else { "gmail_raw" }
$receivedDateTime = ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$rawResponse.internalDate)).LocalDateTime

$SPF = Get-AuthenticationResultValue $Header "spf"
$DKIM = Get-AuthenticationResultValue $Header "dkim"
$DMARC = Get-AuthenticationResultValue $Header "dmarc"

Write-Host ""
Write-Host "===== GMAIL DMARC TEST RESULT ====="
Write-Host "Header  : $HeaderSource"
Write-Host "SPF   : $SPF"
Write-Host "DKIM  : $DKIM"
Write-Host "DMARC : $DMARC"
Write-Host ""

[PSCustomObject]@{
    DateTime = Get-Date
    Sender = $SenderMailbox
    Receiver = $ReceiverMailbox
    Subject = $Subject
    ReceivedDateTime = $receivedDateTime
    SPF = $SPF
    DKIM = $DKIM
    DMARC = $DMARC
    AuthenticationResults = $Header
} | Export-Csv `
        $ResultFile `
        -NoTypeInformation `
        -Append `
        -Encoding UTF8

Write-Host "CSV Recorded : $ResultFile"
Write-Host ""
