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
$SenderMailbox   = "user001@chat.e-postinc.jp"
$ReceiverMailbox = "leehokang@gmail.com"
$GraphSenderUser = "me"
$GraphReceiverUser = "me"
$GraphScopes     = "https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/Mail.Read offline_access"
$SendMethod      = "Smtp"
$SmtpHost        = "219.163.190.214"
$SmtpPort        = [int]$M365AuthGuiAccount.smtp_port
$SmtpMode        = "Raw"
$SmtpAuthUser    = "user001"
$SmtpAuthPassword = $null
$SmtpVerbose     = $false

$GmailSenderMailbox = "leehokang@gmail.com"
$GmailReceiverMailbox = "leehokang@gmail.com"
$GmailClientSecretFile = ".\gmail_client_secret.json"
if (!(Test-Path -LiteralPath $GmailClientSecretFile) -and (Test-Path -LiteralPath ".\gmail_client_secret.json.json"))
{
    $GmailClientSecretFile = ".\gmail_client_secret.json.json"
}
$GmailTokenFile = ".\Result\gmail_token.json"
$GmailScopes = "https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly"
$GmailRedirectPort = 8765

$TestSubject      = "DMARC TEST"

$ResultFolder     = ".\Result"
$ResultFile       = ".\Result\DMARC_Test_Result.csv"
$GraphTokenFile   = ".\Result\graph_token.json"

$WaitSeconds      = 60

$LocalConfigFile = ".\Config.local.ps1"
if (Test-Path -LiteralPath $LocalConfigFile)
{
    . $LocalConfigFile
}
