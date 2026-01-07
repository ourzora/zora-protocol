# Protocol Knowledge Base

This file contains institutional knowledge about protocol integrations, non-obvious behaviors, and lessons learned from development. AI agents should reference this when writing or reviewing protocol code, and should add new entries when discovering nuances.

## How to Use This File

**When writing protocol code:** Review relevant sections before implementation.
**When fixing bugs:** If the fix involves a non-obvious protocol behavior, add an entry.
**When reviewing code:** Check if the code respects known nuances in this file.

---

## Uniswap V4

_(Add entries as discovered)_

---

## Solidity Patterns

_(Add entries as discovered)_

---

## Zora-Specific Patterns

_(Add entries as discovered)_

---

## Entry Template

When adding new entries, use this format:

```markdown
### Brief Title

**The Issue:** One-sentence description of the non-obvious behavior.

**Wrong:**

\`\`\`solidity
// Code that demonstrates the mistake
\`\`\`

**Correct:**

\`\`\`solidity
// Code that demonstrates the fix
\`\`\`

**Reference:** Link to documentation or source code (if applicable)
```
