# ====================================
# Run SMTP to Gmail DMARC Test
# ====================================

. .\Config.ps1

if ($SendMethod -ne "Smtp")
{
    throw "Set `$SendMethod to `"Smtp`" in Config.ps1 before running this test."
}

.\02-Send-TestMail.ps1

.\05-Connect-Gmail.ps1

Write-Host ""
Write-Host "Waiting for Gmail delivery, up to $WaitSeconds sec..."
Write-Host ""

.\07-Check-Gmail-DMARC.ps1
