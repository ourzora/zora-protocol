---
"@zoralabs/protocol-deployments": patch
---

Fix critical security vulnerabilities with pnpm overrides

- Added pnpm overrides to eliminate critical vulnerabilities
- Fixed vitest RCE vulnerability (^2.1.9)
- Fixed elliptic private key extraction vulnerability (^6.6.1)  
- Fixed ejs template injection vulnerability (^3.1.7)
- Fixed pbkdf2 input validation vulnerability (^3.1.3)
- Fixed form-data boundary generation vulnerability (^4.0.4)
- Fixed braces ReDoS vulnerability (^3.0.3)
- Fixed sha.js type checking vulnerability (^2.4.12)
