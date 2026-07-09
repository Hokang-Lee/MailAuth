# ====================================
# Run Gmail All
# ====================================

. .\Config.ps1

.\05-Connect-Gmail.ps1

.\06-Send-Gmail-TestMail.ps1

Write-Host ""
Write-Host "Waiting for Gmail delivery, up to $WaitSeconds sec..."
Write-Host ""

.\07-Check-Gmail-DMARC.ps1
