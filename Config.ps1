# ====================================
# Microsoft 365 DMARC Test Config
# ====================================

$M365AuthGuiAccountFile = Join-Path $env:USERPROFILE "Documents\M365AuthGUI\files0527\accounts.json"
$M365AuthGuiAccountName = "EPST-LEE"

if (!(Test-Path -LiteralPath $M365AuthGuiAccountFile))
{
    throw "M365AuthGUI accounts.json not found: $M365AuthGuiAccountFile"
}

$M365AuthGuiAccounts = Get-Content -LiteralPath $M365AuthGuiAccountFile -Encoding UTF8 |
    ConvertFrom-Json

if ($M365AuthGuiAccountName)
{
    $M365AuthGuiAccount = $M365AuthGuiAccounts |
        Where-Object { $_.name -eq $M365AuthGuiAccountName } |
        Select-Object -First 1
}
else
{
    $M365AuthGuiAccount = $M365AuthGuiAccounts | Select-Object -First 1
}

if (!$M365AuthGuiAccount)
{
    throw "M365AuthGUI account not found: $M365AuthGuiAccountName"
}

$TenantId        = $M365AuthGuiAccount.tenant_id
$ClientId        = $M365AuthGuiAccount.client_id
$SenderMailbox   = "epost_sales_tec@e-postinc.jp"
$ReceiverMailbox = "user001@chat.e-postinc.jp"
$GraphSenderUser = "me"
$GraphReceiverUser = "me"
$GraphScopes     = "https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/Mail.Read offline_access"
$SendMethod      = "Smtp"
$SmtpHost        = $M365AuthGuiAccount.smtp_host
$SmtpPort        = [int]$M365AuthGuiAccount.smtp_port

$TestSubject      = "DMARC TEST"

$ResultFolder     = ".\Result"
$ResultFile       = ".\Result\DMARC_Test_Result.csv"
$GraphTokenFile   = ".\Result\graph_token.json"

$WaitSeconds      = 60
