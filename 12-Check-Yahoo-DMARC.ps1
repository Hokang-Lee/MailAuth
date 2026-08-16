# ====================================
# Yahoo DMARC Check
# ====================================

param(
    [string]$HeaderFile
)

$ErrorActionPreference = "Stop"

. .\Config.ps1

if ($HeaderFile)
{
    $YahooHeaderFile = $HeaderFile
}

function Get-HeaderValuesFromRawMessage($RawMessage, $HeaderName)
{
    $normalized = $RawMessage -replace "`r`n", "`n"
    $headerEnd = $normalized.IndexOf("`n`n")

    if ($headerEnd -ge 0)
    {
        $headerText = $normalized.Substring(0, $headerEnd)
    }
    else
    {
        $headerText = $normalized
    }

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

function Get-HeaderValue($RawMessage, $HeaderName)
{
    $values = Get-HeaderValuesFromRawMessage $RawMessage $HeaderName
    $values | Select-Object -First 1
}

if (!(Test-Path -LiteralPath $YahooHeaderFile))
{
    throw "Yahoo header file not found: $YahooHeaderFile. Save the full Yahoo message header there, or pass -HeaderFile."
}

if (!(Test-Path $ResultFolder))
{
    New-Item -ItemType Directory -Path $ResultFolder | Out-Null
}

$rawHeader = Get-Content -LiteralPath $YahooHeaderFile -Encoding UTF8 -Raw
$Header = (Get-HeaderValuesFromRawMessage $rawHeader "Authentication-Results") -join "`n"
$HeaderSource = if ([string]::IsNullOrWhiteSpace($Header)) { "not_found" } else { "yahoo_header_file" }

$Subject = if (Test-Path -LiteralPath ".\last_subject.txt")
{
    Get-Content .\last_subject.txt -Encoding UTF8 | Select-Object -First 1
}
else
{
    Get-HeaderValue $rawHeader "Subject"
}

$receivedDateTime = Get-HeaderValue $rawHeader "Date"
if ([string]::IsNullOrWhiteSpace($receivedDateTime))
{
    $receivedDateTime = Get-Date
}

$SPF = Get-AuthenticationResultValue $Header "spf"
$DKIM = Get-AuthenticationResultValue $Header "dkim"
$DMARC = Get-AuthenticationResultValue $Header "dmarc"

Write-Host ""
Write-Host "===== YAHOO DMARC TEST RESULT ====="
Write-Host "Header  : $HeaderSource"
Write-Host "SPF   : $SPF"
Write-Host "DKIM  : $DKIM"
Write-Host "DMARC : $DMARC"
Write-Host ""

[PSCustomObject]@{
    DateTime = Get-Date
    Sender = $SenderMailbox
    Receiver = $YahooReceiverMailbox
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
