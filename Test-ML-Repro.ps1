$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $root = Join-Path $PSScriptRoot 'Result/ML-Repro'
    function Invoke-Prepared($Arguments) {
        $before = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        & ./13-Run-ML-DMARC-Repro.ps1 @Arguments
        $created = @(Get-ChildItem $root -Directory | Where-Object Name -NotIn $before)
        if ($created.Count -ne 1) { throw 'Expected one prepared case.' }
        $manifest = Get-Content (Join-Path $created[0].FullName 'manifest.json') -Raw | ConvertFrom-Json
        if ($manifest.Status -ne 'Prepared' -or $manifest.Authentication -ne 'NOT_CHECKED') { throw 'Incorrect status.' }
        if ($Arguments.DeliveryHost -and ($manifest.SmtpHost -ne $Arguments.DeliveryHost -or $manifest.SmtpPort -ne 25 -or $manifest.SmtpAuthEnabled)) { throw 'Delivery override or credential isolation failed.' }
        return [IO.File]::ReadAllText((Join-Path $created[0].FullName 'message.eml'), [Text.Encoding]::GetEncoding(28591))
    }
    $baseline = Invoke-Prepared @{ EnvelopeFrom='list@example.net'; HeaderFrom='author@example.org'; SenderHeader='list@example.net'; Receiver='recipient@example.com' }
    if ($baseline -notmatch '(?m)^From: author@example.org\r?$' -or $baseline -notmatch '(?m)^Sender: list@example.net\r?$') { throw 'Address separation failed.' }
    # Structural fixture only: this is not a cryptographically valid signature.
    $null = Invoke-Prepared @{ DeliveryHost='192.168.1.3'; DeliveryNoAuth=$true }
    $rejected = $false
    try { & ./13-Run-ML-DMARC-Repro.ps1 -DeliveryHost '192.168.1.3' } catch { $rejected = $true }
    if (!$rejected) { throw 'Alternate host silently inherited credentials.' }
    # Structural fixture only: this is not a cryptographically valid signature.
    $fixture = "DKIM-Signature: v=1; d=example.org; s=test; h=from:subject; bh=fixture; b=fixture`r`n" + $baseline
    $fixturePath = Join-Path $root 'structural-fixture.eml'
    [IO.File]::WriteAllText($fixturePath, $fixture, [Text.Encoding]::GetEncoding(28591))
    $unchanged = Invoke-Prepared @{ OriginalEml=$fixturePath }
    if ($unchanged -cne $fixture) { throw 'Unchanged replay modified bytes.' }
    $subject = Invoke-Prepared @{ OriginalEml=$fixturePath; Variant='Subject' }
    if ($subject.Replace('Subject: [ML001] ', 'Subject: ') -cne $fixture) { throw 'Subject replay changed other bytes.' }
    $body = Invoke-Prepared @{ OriginalEml=$fixturePath; Variant='Body' }
    if ($body -cne ($fixture.TrimEnd("`r", "`n") + "`r`n`r`nML test footer: count=001`r`n")) { throw 'Body replay changed other bytes.' }
    $rejected = $false
    try { & ./13-Run-ML-DMARC-Repro.ps1 -HeaderFrom "bad`r`nInjected: value" } catch { $rejected = $true }
    if (!$rejected) { throw 'Header injection accepted.' }
    [IO.File]::WriteAllText($fixturePath, $baseline, [Text.Encoding]::GetEncoding(28591))
    $rejected = $false
    try { & ./13-Run-ML-DMARC-Repro.ps1 -OriginalEml $fixturePath } catch { $rejected = $true }
    if (!$rejected) { throw 'Unsigned source accepted.' }
    Write-Host 'PASS: preparation, separate addresses, byte preservation, subject/body variants, injection rejection, unsigned rejection. No email sent; DKIM not verified.'
} finally { Pop-Location }
