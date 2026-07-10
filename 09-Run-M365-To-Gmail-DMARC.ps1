# ====================================
# Run Microsoft 365 to Gmail DMARC Test
# ====================================

. .\Config.ps1

.\01-Connect-M365.ps1

.\02-Send-TestMail.ps1 `
    -Method "Graph" `
    -Sender $M365SenderMailbox `
    -Receiver $GmailReceiverMailbox `
    -GraphSender $GraphSenderUser

.\05-Connect-Gmail.ps1

Write-Host ""
Write-Host "Waiting for Gmail delivery, up to $WaitSeconds sec..."
Write-Host ""

.\07-Check-Gmail-DMARC.ps1
