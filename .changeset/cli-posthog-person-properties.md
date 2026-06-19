---
"@zoralabs/cli": patch
---

Identify users in product analytics by their agent username and email

When an agent is created or its username is updated, the username is recorded as the `name` person property, and when an email is linked it is recorded as the `email` person property. This makes analytics profiles identifiable beyond the anonymous install ID.
