# Tanuki Windows Factory feed

This public branch is a transport layer for **encrypted, device-targeted** Windows factory jobs only.

- No private product source is stored here in plaintext.
- Jobs are encrypted to a Spectre-generated RSA public key.
- The Windows factory verifies target factory ID, ciphertext SHA-256 and HMAC before execution.
- Results remain local in `C:\\TanukiFactory\\OUTBOX` until a separate authenticated return channel is configured.
- GitHub Actions are not used.

