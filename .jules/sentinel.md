## 2024-01-01 - Replace Get-Random with CSPRNG
**Vulnerability:** Weak random number generation using Get-Random
**Learning:** Generating passwords using Get-Random is cryptographically insecure because it relies on a PRNG.
**Prevention:** Always use [System.Security.Cryptography.RandomNumberGenerator] for security-critical randomness such as passwords, tokens, or encryption keys.
