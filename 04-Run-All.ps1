# ====================================
# Run All
# ====================================

. .\Config.ps1

.\01-Connect-M365.ps1

.\02-Send-TestMail.ps1

Write-Host ""
Write-Host "Waiting for delivery, up to $WaitSeconds sec..."
Write-Host ""

.\03-Check-DMARC.ps1
