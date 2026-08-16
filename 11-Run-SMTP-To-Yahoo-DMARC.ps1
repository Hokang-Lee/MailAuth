# ====================================
# Run SMTP to Yahoo DMARC Test
# ====================================

$ErrorActionPreference = "Stop"

. .\Config.ps1

if ($SendMethod -ne "Smtp")
{
    throw "Set `$SendMethod to `"Smtp`" in Config.ps1 before running this test."
}

.\02-Send-TestMail.ps1 `
    -Method "Smtp" `
    -Receiver $YahooReceiverMailbox

Write-Host ""
Write-Host "Yahoo mail sent."
Write-Host "Open the received message in Yahoo Mail, copy the full header, save it to:"
Write-Host "  $YahooHeaderFile"
Write-Host ""
Write-Host "Then run:"
Write-Host "  .\12-Check-Yahoo-DMARC.ps1"
Write-Host ""
