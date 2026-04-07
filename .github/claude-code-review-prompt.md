Please review this pull request and provide feedback on:

- Code quality and best practices
- Potential bugs or issues
- Performance considerations
- Security concerns
- Test coverage

**Important: Changeset Validation**
If this PR modifies contract code (_.sol files in packages/_/src/), validate changesets:

1. **Identify what changed in this PR**:

   - Examine the PR diff provided by the action (NOT hardcoded `main`)
   - Identify which Solidity files and functions were modified
   - Read commit messages in the PR to understand the changes

2. **Check for changesets added in this PR**:

   - Look at the diff to see if any `.changeset/*.md` files were added or modified
   - Separate changesets that exist in base branch (upstream) vs added in this PR

3. **For stacked diffs, determine if upstream changesets cover this PR**:

   - If changesets exist in base branch, read their content
   - Assess if the upstream changeset descriptions match the contract changes in THIS PR
   - A changeset only covers this PR if it specifically describes the changes made here

4. **Validate changeset relevance**:

   - A changeset is valid for this PR if it:
     - Mentions the specific contract or function being modified in this PR
     - Describes the actual change being made (e.g., "fix double-counting", "add new feature")
     - Targets the correct package (e.g., "@zoralabs/coins" for packages/coins/src changes)

5. **If contract code changed but no relevant changeset**:
   - Determine if changes are related to an upstream changeset (if this is a stacked diff)
   - If related to upstream changeset: suggest updating the existing changeset
   - If new/unrelated changes: remind author to create new changeset using `pnpm changeset add --empty`
   - According to CLAUDE.md: "When updating contract code, make a changeset for the corresponding contract package"

**Important: ABI Stability**
If this PR modifies interface files (I*.sol files in packages/*/src/):

1. **Events**: NEVER modify existing event signatures
   - Adding/removing/reordering parameters breaks the ABI
   - For new functionality, create a NEW event (e.g., `CoinCreatedV2` instead of modifying `CoinCreated`)
   - Event removal requires `@custom:deprecated` annotation in a prior release

2. **Functions**: Follow these rules
   - ✅ Adding new functions is allowed
   - ✅ Renaming parameters is allowed (doesn't affect selector)
   - ❌ Renaming functions is NOT allowed (creates confusion)
   - ❌ Changing parameter types is NOT allowed (changes selector)
   - ❌ Removing functions requires `@custom:deprecated` annotation in a prior release

3. **Deprecation workflow** (required before removal):
   ```solidity
   /// @custom:deprecated Use newFunction() instead. Will be removed in vX.Y.
   function oldFunction(...) external;
   ```
   - First PR: Add `@custom:deprecated` annotation, run `pnpm run abi-check:generate`, release
   - Second PR (later): Remove the function, run `pnpm run abi-check:generate`

4. **If ABI changes detected**: Remind author to run `pnpm run abi-check:generate` to update the baseline
   after confirming the change is intentional and follows the deprecation workflow.

External indexers, SDKs, and frontends depend on stable ABIs. Breaking changes cause silent failures.

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
