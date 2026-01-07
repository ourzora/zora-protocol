Please review this pull request and provide feedback on:
- Code quality and best practices
- Potential bugs or issues
- Performance considerations
- Security concerns
- Test coverage

**Important: Changeset Validation**
If this PR modifies contract code (*.sol files in packages/*/src/), please check:
1. Is there a changeset file in .changeset/ directory?
2. If contract code changed but no changeset exists, remind the author to add one using `pnpm changeset add --empty` and manually edit it
3. According to CLAUDE.md: "When updating contract code, make a changeset for the corresponding contract package"

**Important: Protocol Knowledge Base**
If this PR fixes a bug related to protocol integration nuances (e.g., Uniswap V4 behavior,
external protocol gotchas, non-obvious Solidity patterns):
1. Check if PROTOCOL_KNOWLEDGE.md was updated
2. If the fix involves a non-obvious behavior that others could encounter, suggest adding
   an entry to PROTOCOL_KNOWLEDGE.md documenting:
   - What the non-obvious behavior is
   - Wrong vs correct code patterns
   - Reference links if applicable

This helps build institutional knowledge for future development.

Be constructive and helpful in your feedback.
