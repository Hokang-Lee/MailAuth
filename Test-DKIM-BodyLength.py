"""Exercise DKIM l= using dkimpy and a local DNS callback; no email is sent."""
import base64
import json
from datetime import datetime
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "Result" / "dkim-test-deps"))
import dkim
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def main():
    output = ROOT / "Result" / "DKIM-BodyLength" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    output.mkdir(parents=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private = key.private_bytes(serialization.Encoding.PEM,
                                serialization.PrivateFormat.TraditionalOpenSSL,
                                serialization.NoEncryption())
    public = key.public_key().public_bytes(serialization.Encoding.DER,
                                           serialization.PublicFormat.SubjectPublicKeyInfo)
    txt = b"v=DKIM1; k=rsa; p=" + base64.b64encode(public)
    (output / "public-key.txt").write_bytes(txt)

    def dns(name, timeout=5):
        if name.rstrip(b".").lower() == b"lengthtest._domainkey.example.invalid":
            return txt
        return None

    message = (
        b"From: author@example.invalid\r\n"
        b"To: recipient@example.invalid\r\n"
        b"Subject: DKIM body length test\r\n"
        b"MIME-Version: 1.0\r\n"
        b"Content-Type: text/plain; charset=us-ascii\r\n"
        b"Content-Transfer-Encoding: 7bit\r\n\r\n"
        b"ML DMARC TEST MAIL\r\n"
    )
    rows = []
    for limited in (False, True):
        signature = dkim.sign(message, b"lengthtest", b"example.invalid", private,
                              canonicalize=(b"relaxed", b"relaxed"),
                              include_headers=[b"from", b"to", b"subject", b"mime-version",
                                               b"content-type", b"content-transfer-encoding"],
                              length=limited)
        signed = signature + message
        cases = {
            "unchanged": (signed, True),
            "footer": (signed + b"\r\nML count: 001\r\n", limited),
            "signed_body_edit": (signed.replace(b"ML DMARC TEST MAIL", b"XX DMARC TEST MAIL"), False),
            "subject_edit": (signed.replace(b"Subject: DKIM", b"Subject: [001] DKIM"), False),
        }
        for case, (raw, expected) in cases.items():
            actual = dkim.verify(raw, dnsfunc=dns)
            name = ("limited" if limited else "full") + "-" + case
            (output / (name + ".eml")).write_bytes(raw)
            rows.append({"case": case, "length_tag": limited, "dkim": "PASS" if actual else "FAIL",
                         "expected": "PASS" if expected else "FAIL", "matches": actual == expected})
            print(f"{name:28} DKIM={'PASS' if actual else 'FAIL'} expected={'PASS' if expected else 'FAIL'}")
    (output / "results.json").write_text(json.dumps({
        "verification": "dkimpy with local public-key DNS callback",
        "sent": False, "dmarc": "NOT_TESTED", "results": rows,
    }, indent=2), encoding="utf-8")
    print(f"Results: {output}")
    if not all(row["matches"] for row in rows):
        raise SystemExit("Unexpected DKIM result")


if __name__ == "__main__":
    main()
