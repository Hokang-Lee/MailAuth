# メーリングリストの再現テスト

`13-Run-ML-DMARC-Repro.ps1` は既定ではEMLとmanifest.jsonを `Result/ML-Repro/` に作成します。`-Send` を付けた場合だけ、既存のSMTP設定で送信します。顧客の問い合わせメールを転送する必要はありません。

## 1. 送信元の整合性

```powershell
.\13-Run-ML-DMARC-Repro.ps1 -EnvelopeFrom user001@chat.e-postinc.jp -HeaderFrom user001@chat.e-postinc.jp -Receiver leehokang@gmail.com
```

別の管理下のドメインをHeaderFromに指定すれば、MAIL FROMとの不一致を検証できます。SenderHeaderも指定できます。ただしSenderヘッダーはDMARC整合性の対象ではありません。単にアドレスを変えただけでFAILするとは限らず、受信側で検証されたDKIM署名のd=、SPFのドメイン、Fromの整合を確認します。

## 2. 署名後の変更

自分のテスト用アカウントから送信したDKIM署名付きメールを、受信側から元のEML形式で `Result/original-signed.eml` に保存します。顧客の問い合わせEMLにはDKIM-Signatureがないので、この入力には使えません。

```powershell
.\13-Run-ML-DMARC-Repro.ps1 -OriginalEml .\Result\original-signed.eml -Variant Unchanged
.\13-Run-ML-DMARC-Repro.ps1 -OriginalEml .\Result\original-signed.eml -Variant Subject
.\13-Run-ML-DMARC-Repro.ps1 -OriginalEml .\Result\original-signed.eml -Variant Body
```

各コマンドに `-Send -Receiver leehokang@gmail.com` を付けて送信できます。Replayでは元のFrom/To/Message-IDを保持し、SMTPの配送先だけReceiverで指定します。同じMessage-IDのため受信側でスレッド化・重複扱いになる可能性があります。受信時刻と変更内容で区別してください。

本文追記はtext/plainの7bit/8bit入力用です。multipart、base64、quoted-printableは、MIME再構築の影響を混ぜないため対象外です。CRLFを保持したEMLが必要です。

| ケース | 確認点 |
| --- | --- |
| Unchanged | 元の署名が受信側でもPASSするか。ここがFAILなら変更の比較は成立しない |
| Subject | 元署名のh=にsubjectが含まれる場合、件名変更で元署名がFAILするか |
| Body | 通常は本文ハッシュ不一致。l=で署名範囲を限定した署名は例外になり得る |

元署名のFAILだけでDMARC FAILとは断定できません。整合したSPF、別の整合したDKIM署名がPASSすればDMARCはPASSします。送信サーバーが付ける新しい署名も確認してください。ARCによる配送救済とDMARCの判定は分けて記録します。

## 3. 結果確認

### 別の配送SMTP

192.168.1.3 (smtp-test.jp) を使う場合は次のように指定します。このPCからの認証なしリレーが許可されている構成用です。既存サーバーの資格情報は引き継ぎません。

```powershell
.\13-Run-ML-DMARC-Repro.ps1 -OriginalEml .\Result\original-signed.eml -Variant Subject -Receiver leehokang77@yahoo.co.jp -DeliveryHost 192.168.1.3 -DeliveryPort 25 -DeliveryNoAuth -Send
```

本文追記は `-Variant Body`、変更なしは `-Variant Unchanged` にします。`-Send` を省略すると準備のみです。サーバーの署名設定は変更しません。SMTPのホスト名とDKIMのd=は別の設定なので、配送後の署名と認証結果を確認します。

EML生成とSMTP受付は認証成功を意味しません。manifestのAuthenticationはNOT_CHECKEDのままです。受信側の元メールからAuthentication-Results、すべてのDKIM-Signature、Return-Pathを取得し、各ケースの出力フォルダーに保存してください。ローカルで署名検証やDNS変更は行いません。

Yahooのヘッダーは既存の `12-Check-Yahoo-DMARC.ps1 -HeaderFile <保存ファイル>` で解析可能です。ただし同スクリプトは既存テストのCSV形式であり、複数DKIM署名の比較には生ヘッダーを併用してください。

このテストは顧客の現象の仕組みを再現します。顧客環境の完全再現には、実際のML設定と署名前後のテストメールが必要です。DLLによる本文追記の可否はこの結果では判断できません。

参考: https://www.rfc-editor.org/rfc/rfc6376.html (3.5, 5.3, 5.4)

## l=による本文署名範囲の比較（ローカル）

`Test-DKIM-BodyLength.py` はdkimpyとcryptographyを使い、一時的なRSA鍵で署名と検証を行います。秘密鍵はメモリ内だけに保持します。公開鍵の問い合わせはローカル関数で回答し、DNS変更やメール送信は行いません。

```powershell
python -m pip install --target .\Result\dkim-test-deps dkimpy==1.1.8 cryptography
python .\Test-DKIM-BodyLength.py
```

`l=`なし／ありそれぞれについて、変更なし・末尾追記・署名範囲内の本文変更・件名変更を比較します。公開鍵、各EML、results.jsonを `Result/DKIM-BodyLength/` に保存します。

末尾追記が署名範囲外となる場合のDKIM検証を試すもので、追記内容を認証するものではありません。受信サービスが署名範囲外の内容を拒否する可能性もあります。Yahoo/Gmailでの実配送・DMARC結果は未検証です。既存署名にl=を後付けすることはできず、元の署名者が最初から指定する必要があります。
