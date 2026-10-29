# Main signature preflight (no game launched)

Using cache-only WinVerifyTrust with the candidate's exact flags in an owned
GE-Proton10-34 test prefix:

1. WuWa `Client-Win64-Shipping.exe`: 0x00000000, accepted.
2. HSR `StarRail.exe`: 0x80096004, rejected by this verifier.
3. CP2077 `Cyberpunk2077.exe`: 0x00000000, accepted.

The HSR failure is **not evidence of an altered executable**. Independent
osslsigncode verification of the same file succeeded: embedded image digest,
COGNOSPHERE signature, certificate chain and CRL verification. See
`HSR_OPENSSL_VERIFY.txt` and `HSR_EXE_SHA256SUMS`. That independent verification
did fetch the public DigiCert CRLs; the WinVerifyTrust probe was cache-only.
The reason for the verifier discrepancy has not been isolated.

The local osslsigncode source/build is under `tools/`; `tools/SOURCE_COMMIT`
records the fetched upstream commit. It was not installed system-wide.

No game, account/save, launcher, protected component, certificate store,
Guardian or hardware setting was changed. HSR's future external integrity lease
must use an explicit verified baseline rather than pretending the rejected
Wine result was successful. This does not attest game/anti-cheat permission.
