# Cloud Pairing Certificate Pin Hotfix

## Problem

`Jujo.StreamServer` publishes `cert_fingerprint` as SHA-256 of the certificate
file's raw PEM bytes. PEM formatting is not part of the X.509 identity and can
change across operating systems or serializers. `Jujo.StreamClient` 1.0.19
tries to reconstruct those bytes from the certificate received during TLS.
When the representations differ, TLS is rejected before
`POST /api/pair/cloud` reaches the server.

Cloud sync also marks a computer as paired before that POST succeeds. The UI
therefore reports a paired server while the server has no corresponding client
certificate and `/applist` cannot run.

## Decision

Use SHA-256 of the certificate's DER encoding as the canonical cloud pin.
DER represents the certificate itself and is stable across PEM line endings,
wrapping, and file encodings.

- Server parses its configured X.509 certificate, DER-encodes it, and publishes
  the lowercase 64-character SHA-256 digest in `cert_fingerprint`.
- Client checks a 64-character fingerprint against DER SHA-256 first.
- Client retains the existing PEM-variant check for profiles published by older
  servers and retains exact PEM/hex-PEM and SHA-1 support for manual pairing.
- No trust-all fallback is introduced for cloud pairing or normal NvHTTP.

This is a coordinated protocol correction. Clients older than 1.0.18 already
accept the self-signed server certificate. Client 1.0.19 is already unable to
use affected raw-PEM pins, so changing the server row to DER does not remove a
working strict-pin path.

## Pairing State

A cloud profile means the server belongs to the signed-in account; it does not
prove that this device's client certificate is installed on that server.

- Merging a cloud profile must not force an existing local computer to paired.
- A newly imported cloud computer starts unpaired.
- The initial cloud-pairing attempt still runs automatically.
- Only a successful `POST /api/pair/cloud` sets `PairState.paired` and persists
  it.
- HTTPS polling and `/applist` 401 responses continue to trigger the existing
  one-shot cloud repair path.

## Failure Handling

- Invalid/unreadable server certificates publish no fingerprint and emit a
  warning; the server must not publish a misleading pin.
- A mismatched pin remains a hard TLS failure.
- Cloud pairing business rejection remains non-retryable; transport failures
  retain bounded retries.
- UI errors must distinguish an empty application catalog from certificate or
  authorization rejection when the transport exposes that distinction.

## Regression Coverage

Server tests must prove that equivalent LF and CRLF PEM strings produce the
same DER fingerprint and that invalid PEM is rejected.

Client tests must prove:

- DER SHA-256 matches the live certificate material.
- Wrong DER SHA-256 is rejected.
- Legacy PEM SHA-256, SHA-1, PEM, and hex-PEM remain accepted.
- New cloud profiles are not marked paired before the POST.
- Successful cloud pairing persists the paired state.

## Runtime Acceptance

1. Server heartbeat updates the live cloud row to the DER fingerprint.
2. Client reaches `POST /api/pair/cloud` over pinned TLS.
3. Server persists the device under `named_devices`.
4. Client retrieves a non-empty `/applist` without manual PIN pairing.
5. Restarting either side preserves automatic pairing.
