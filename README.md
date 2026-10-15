# MailAuth

Microsoft 365 / Graph と Gmail API を使ったメール認証テスト用スクリプトです。

成果物は大きく2系統です。

1. Microsoft 365 / Graph 認証テスト
2. SMTP AUTH送信 + Gmail DMARC確認テスト
3. SMTP AUTH送信 + Yahoo DMARC確認テスト

## 1. Microsoft 365 / Graph 認証テスト

Microsoft 365 の Graph API に接続し、テストメール送信、受信確認、`Authentication-Results` 取得、SPF/DKIM/DMARC判定、CSV記録を行う系統です。

主なスクリプト:

```text
01-Connect-M365.ps1   Microsoft Graph OAuth / token取得
02-Send-TestMail.ps1  GraphまたはSMTPでテストメール送信
03-Check-DMARC.ps1    Graph mailboxから受信メールを検索し認証結果取得
04-Run-All.ps1        Microsoft 365側の一括実行
09-Run-M365-To-Gmail-DMARC.ps1  M365送信 + Gmail側確認
```

一括実行:

```powershell
.\04-Run-All.ps1
```

`04-Run-All.ps1` はMicrosoft 365 / Graphの接続、送信、受信確認を検証するためのスクリプトです。Graphで内部送信する場合、`Authentication-Results` が付かないことがあるため、DMARC判定そのものはGmail側のテストで確認します。

M365からGmailへ送り、Gmail側で確認する場合:

```powershell
.\09-Run-M365-To-Gmail-DMARC.ps1
```

`09-Run-M365-To-Gmail-DMARC.ps1` もGraph送信を明示して実行し、受信確認だけをGmail APIで行います。

## 2. SMTP AUTH送信 + Gmail DMARC確認テスト

現在の成功パターンです。

`user001@chat.e-postinc.jp` から `leehokang@gmail.com` へ SMTP AUTH で送信し、Gmail API で受信メールの `Authentication-Results` を取得します。

一括実行:

```powershell
.\10-Run-SMTP-To-Gmail-DMARC.ps1
```

処理内容:

1. `219.163.190.214` へ SMTP AUTH で送信
2. Gmail OAuth tokenを更新または再利用
3. Gmailから該当件名のraw messageを取得
4. `Authentication-Results` から `SPF` / `DKIM` / `DMARC` を抽出
5. `Result\DMARC_Test_Result.csv` に記録

主なスクリプト:

```text
05-Connect-Gmail.ps1             Gmail OAuth接続
07-Check-Gmail-DMARC.ps1         Gmail raw messageから認証結果取得
10-Run-SMTP-To-Gmail-DMARC.ps1   SMTP AUTH送信 + Gmail認証結果取得
```

## 3. SMTP AUTH送信 + Yahoo DMARC確認テスト

Yahoo Mail宛にSMTP AUTHで送信し、Yahooの詳細ヘッダーを解析して `SPF` / `DKIM` / `DMARC` をCSVに記録します。

送信:

```powershell
.\11-Run-SMTP-To-Yahoo-DMARC.ps1
```

Yahoo Mailで受信メールの詳細ヘッダーをコピーし、既定では以下に保存します。

```text
Result\Yahoo_Last_Header.txt
```

解析:

```powershell
.\12-Check-Yahoo-DMARC.ps1
```

別ファイルを解析する場合:

```powershell
.\12-Check-Yahoo-DMARC.ps1 -HeaderFile .\Result\Yahoo_Header_20260816.txt
```

## 成功確認済みの結果

2026-07-10 のテストでは以下を確認しました。

```text
From  : user001@chat.e-postinc.jp
To    : leehokang@gmail.com
SMTP  : 219.163.190.214
Auth  : user001

SPF   : SOFTFAIL
DKIM  : PASS
DMARC : PASS
```

SPFはsoftfailですが、`d=chat.e-postinc.jp` のDKIMがPASSし、Fromドメインと整合しているためDMARCはPASSしています。

## MLの再現テスト

`13-Run-ML-DMARC-Repro.ps1` で送信元の整合性と署名後の件名・本文変更を比較します。手順と判定上の注意は [ML-Repro.md](ML-Repro.md) を参照してください。既定では送信せず、テストEMLを生成します。

## 設定

基本設定は `Config.ps1` です。

秘密情報や端末固有の値は `Config.local.ps1` に置きます。このファイルは `.gitignore` 対象です。

作成例:

```powershell
Copy-Item .\Config.local.example.ps1 .\Config.local.ps1
```

`Config.local.ps1` にSMTPパスワードを設定します。

```powershell
$SmtpAuthPassword = "your-password"
```

## CSV出力

認証結果は以下に追記されます。

```text
Result\DMARC_Test_Result.csv
```

列:

```text
DateTime, Sender, Receiver, Subject, ReceivedDateTime, SPF, DKIM, DMARC, AuthenticationResults
```

## Gitに入れないもの

```text
Config.local.ps1
Result/
last_subject.txt
gmail_client_secret*.json
```
