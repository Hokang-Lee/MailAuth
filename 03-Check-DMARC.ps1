# ====================================
# DMARC Check
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
    if ($Header -match "(?i)\b$Name=([a-z0-9_-]+)")
    {
        return $matches[1].ToUpperInvariant()
    }

    return "NOT_FOUND"
}

if (!(Test-Path $ResultFolder))
{
    New-Item `
      -ItemType Directory `
      -Path $ResultFolder | Out-Null
}

$Subject = (Get-Content .\last_subject.txt -Encoding UTF8 | Select-Object -First 1)
$EscapedSubject = $Subject.Replace("'", "''")
if ($GraphReceiverUser -eq "me")
{
    $MessageUriBase = "https://graph.microsoft.com/v1.0/me/messages"
}
else
{
    $EncodedReceiver = [System.Uri]::EscapeDataString($GraphReceiverUser)
    $MessageUriBase = "https://graph.microsoft.com/v1.0/users/$EncodedReceiver/messages"
}

$Filter = [System.Uri]::EscapeDataString("subject eq '$EscapedSubject'")
$Select = [System.Uri]::EscapeDataString("id,subject,receivedDateTime,internetMessageHeaders")
$Deadline = (Get-Date).AddSeconds($WaitSeconds)
$mail = $null

do
{
    $response = Invoke-RestMethod `
        -Uri "$($MessageUriBase)?`$filter=$Filter&`$select=$Select&`$top=1" `
        -Method GET `
        -Headers $Headers `
        -TimeoutSec 30

    $mail = $response.value | Select-Object -First 1

    if (!$mail)
    {
        Start-Sleep -Seconds 5
    }
}
while (!$mail -and (Get-Date) -lt $Deadline)

if (!$mail)
{
    Write-Host ""
    Write-Host "Mail not found"
    Write-Host ""
    exit
}

$AuthenticationResults = @(
    $mail.internetMessageHeaders |
    Where-Object name -eq "Authentication-Results"
)

$Header = ($AuthenticationResults.value -join "`n")
$HeaderSource = "internetMessageHeaders"

if ([string]::IsNullOrWhiteSpace($Header))
{
    $rawResponse = Invoke-WebRequest `
        -Uri "$($MessageUriBase)/$($mail.id)/`$value" `
        -Method GET `
        -Headers $Headers `
        -UseBasicParsing `
        -TimeoutSec 30

    $Header = (Get-HeaderValuesFromRawMessage $rawResponse.Content "Authentication-Results") -join "`n"
    $HeaderSource = "mime"
}

if ([string]::IsNullOrWhiteSpace($Header))
{
    $HeaderSource = "not_found"
}

$SPF = Get-AuthenticationResultValue $Header "spf"
$DKIM = Get-AuthenticationResultValue $Header "dkim"
$DMARC = Get-AuthenticationResultValue $Header "dmarc"

Write-Host ""
Write-Host "===== DMARC TEST RESULT ====="
Write-Host "Received : $($mail.receivedDateTime)"
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

    ReceivedDateTime = $mail.receivedDateTime

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
