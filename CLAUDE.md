# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**For comprehensive technical architecture and monorepo details, see [MONOREPO_ARCHITECTURE.md](MONOREPO_ARCHITECTURE.md).**

## Documentation Philosophy

### Contract Documentation Guidelines

When documenting contracts, focus on **how to use** and **how it works** rather than technical reference material:

- **Prioritize user goals**: What does someone want to accomplish? (e.g., "Create a coin", "Understand rewards")
- **Use practical examples**: Show real code snippets and configuration values
- **Explain the "why"**: Help users understand the purpose and trade-offs of different options
- **Visual diagrams**: Use UML diagrams to show relationships and processes
- **Avoid redundancy**: Don't repeat information covered in other sections
- **Remove deprecated methods**: Only document current recommended approaches

### Writing Style for Contracts

- Use action-oriented headings (e.g., "Creating a Coin" vs "Coin Creation")
- Lead with benefits and outcomes, not implementation details
- Include decision-making guidance (e.g., "Use this configuration if...", "Choose based on...")
- Link strategically to related concepts and next steps

## Development Commands

### GitHub Actions Integration

**Claude Code Review Workflow:**

- Automatically runs on PRs with contract code changes
- Validates changeset presence for contract modifications
- Uses sticky comments to update reviews instead of creating multiple comments
- Configured with specific file path triggers and allowed tools for comprehensive validation
- Can be customized with different prompts based on PR author or file types

### Package Management

- `pnpm install` - Install dependencies
- `pnpm build` - Build all packages (full contract compilation + TypeScript builds)
- `pnpm build:js` - Build TypeScript packages only (faster, for docs/development)
- `pnpm test` - Run tests across all packages
- `pnpm dev` - Run development mode with watch tests
- `pnpm lint` - Run linting
- `pnpm format` - Format code with prettier

**For technical details on build system architecture and package patterns, see [MONOREPO_ARCHITECTURE.md](MONOREPO_ARCHITECTURE.md#build-system-architecture).**

### Code Formatting

**CRITICAL: Always run formatting after editing files to ensure proper formatting**

Claude Code must automatically run formatting after making any code changes:

- **Required after every edit**: Run `npx prettier --write <filename>` immediately after editing any file
- **Maintains consistency**: Ensures consistent formatting across the entire monorepo
- **Prevents lint failures**: Avoids formatting-related lint errors in CI/CD pipelines
- **Pre-commit requirement**: Code must be properly formatted before committing changes

**Formatting Commands:**

- **Primary command**: `npx prettier --write <filename>` - Format specific files
- **Root level**: `pnpm format` - Format all packages (when turbo format task is available)
- **Direct**: `npx prettier --write .` - Format all files in current directory
- **Verification**: `npx prettier --check .` - Check if files need formatting (without writing)

### Building & Release

- `pnpm build:docs:coins` - Build coins documentation site
- `pnpm build:docs:nft` - Build NFT documentation site
- `pnpm update-version` - Update package versions using changesets
- `pnpm release` - Build and publish packages

**For detailed build optimization strategies and dependency analysis, see [MONOREPO_ARCHITECTURE.md](MONOREPO_ARCHITECTURE.md#build-optimization-learnings).**

### Changesets

When making changes that affect public APIs or require version updates:

- `pnpm changeset` - Create a changeset describing your changes (interactive mode)
- `pnpm changeset add --empty` - Create an empty changeset file to manually edit
- Follow the interactive prompts to select packages and change types (patch, minor, major)
- Commit the generated changeset file along with your changes
- Changesets are used for automated version management and release notes

**Creating Empty Changesets for Manual Editing:**

- Use `pnpm changeset add --empty` to create an empty changeset file
- This generates a .changeset/\*.md file that you can manually edit
- The file format should follow this structure:

  ```md
  ---
  "@zoralabs/package-name": patch | minor | major
  ---

  Description of changes

  - Bullet point details of what changed
  - Additional context or breaking changes
  ```

**Package Selection Guidelines:**

- **When updating contract code**: Create changeset for the corresponding contract package
- **When updating deployment addresses or ABIs that need to be published**: Create changeset for `@zoralabs/protocol-deployments` (not the individual contract packages)
- **Rationale**: Individual contract packages don't publish addresses - only `@zoralabs/protocol-deployments` does. Deployment addresses and ABIs are consolidated and published through the protocol-deployments package to maintain a dependency-free consumer experience.

**Automated Changeset Validation:**
The Claude Code Review GitHub Action automatically validates that changesets are included when contract code is modified:

- Triggers on PRs that modify `.sol` files in `packages/*/src/`
- Also triggers on PR updates (`synchronize` event) not just creation
- Checks for presence of changeset files in `.changeset/` directory
- Reminds authors to add changesets when missing
- Uses `use_sticky_comment: true` to update existing comments rather than creating new ones
- Provides Claude with tools to inspect changesets: `pnpm changeset status`, `ls .changeset/`, etc.
- **Important**: When deployment files or ABIs are modified, the action should remind developers that `@zoralabs/protocol-deployments` changesets may be needed rather than individual contract package changesets

**For complete details on the protocol-deployments publication workflow, see [MONOREPO_ARCHITECTURE.md](MONOREPO_ARCHITECTURE.md#how-to-publish-a-contract-in-protocol-deployments).**

**Changeset and PR Description Writing Guidelines:**

- **Focus on the feature/fix, not the implementation**: Describe what changed from a user perspective and why it matters
- **Avoid mentioning test coverage**: Don't write about adding tests, test files, or test coverage in changesets or PR descriptions
- **Explain the problem and solution**: Start with the problem being solved, then describe the solution and its impact
- **Use business/user language**: Write for developers who will use the feature, not for those reviewing the implementation
- **Example**: Instead of "Add test for ETH fallback mechanism", write "Fix ETH transfer failures when platform referrers cannot accept ETH"

### Testing

Tests are primarily Solidity-based using Foundry. For individual packages:

- Navigate to package directory (e.g., `cd packages/coins`)
- `FOUNDRY_PROFILE=dev forge test -vvv` - Run Solidity tests with verbose output (recommended)
- `FOUNDRY_PROFILE=dev forge test --watch -vvv` - Run tests in watch mode
- `FOUNDRY_PROFILE=dev forge test -vvv --match-test {test_name}` - Run specific test
- `pnpm test` - Run JavaScript/TypeScript tests

**Test Command Notes:**

- Use `FOUNDRY_PROFILE=dev` for faster test execution
- Alternative: `forge test -vvv` (uses default profile, may be slower)

### Coverage Analysis

To check test coverage for contracts:

**Generate Coverage Report:**

- `cd packages/{package-name}` (e.g., `cd packages/coins`)
- `pnpm run coverage` - Generate LCOV coverage report
- This runs: `forge coverage --report lcov --ir-minimum --no-match-coverage '(test/|src/utils/uniswap/|script/)'`

**Analyze Coverage Results:**

- Coverage report saved to `lcov.info` file
- Parse with:
  <!-- cSpell:ignore gsub -->
  ```bash
  awk '/^SF:src\// { file = $0; gsub("SF:", "", file); } /^LF:/ { total = $0; gsub("LF:", "", total); } /^LH:/ { covered = $0; gsub("LH:", "", covered); if (total > 0) printf "%-50s %3d/%3d lines (%5.1f%%)\n", file, covered, total, (covered/total)*100; }' lcov.info
  ```

**Coverage Exclusions:**

- Check `.github/workflows/contracts.yml` for package-specific `ignore_coverage_files`
- Each package may exclude different files (e.g., `*test*`, `*lib*`, `*uniswap*`, etc.)
- Scripts and deployment files typically excluded via forge coverage flags

**CI Coverage:**

- Coverage checked automatically in GitHub Actions
- Minimum threshold varies by package (check contracts.yml)
- Coverage artifacts uploaded for failed runs
- LCOV reports available for download from CI runs

### Bug Fix Workflow

For Solidity bugs:

1. Write a test to simulate the bug
2. Run the test with `FOUNDRY_PROFILE=dev forge test -vvv` to verify it fails
3. Fix the code to make the test pass
4. Verify the fix with the test suite
5. **Format the code**: Run `pnpm format` to ensure consistent formatting
6. **If the fix involves a non-obvious protocol behavior**: Add an entry to `PROTOCOL_KNOWLEDGE.md`

### Protocol Knowledge Base

A `PROTOCOL_KNOWLEDGE.md` file exists at the repository root containing institutional knowledge about protocol integrations, non-obvious behaviors, and lessons learned.

**When to reference:** Before writing or reviewing protocol code that interacts with external protocols (Uniswap V4, etc.) or involves complex Solidity patterns.

**When to contribute:** Add a new entry when discovering a non-obvious behavior while:

- Fixing a bug related to protocol integration
- Writing new protocol code and finding documentation gaps
- Reviewing code and noticing a subtle correctness issue

**How to contribute:** Add a new entry following the template in the file. Include:

- Brief title describing the nuance
- One-sentence description of the non-obvious behavior
- Code example showing wrong vs correct approach
- Reference link if applicable

### New Feature Workflow

For new features:

1. Add minimal code to get feature compiling
2. Compile with `FOUNDRY_PROFILE=dev forge build` (fails within seconds if there are compilation issues)
3. Write tests to verify feature works
4. **Format the code**: Run `pnpm format` to ensure consistent formatting
5. Commit code
6. Submit PR with `gt submit`

**Build Command Notes:**

- Use `FOUNDRY_PROFILE=dev forge build` for faster compilation feedback
- This profile provides immediate feedback on compilation errors (fails within seconds if there are issues)
- Compilation errors appear instantly - if the build runs for a few seconds without failing, compilation is successful
- The full compilation may take 30+ seconds, but can be interrupted once success is confirmed
- Alternative: `forge build` (uses default profile, may be slower)

## Development Workflow

Uses Graphite for branch management:

**Creating Branches:**

- `gt create {branch_name}` - Create a new branch stacked on current branch
- `gt create -a -m "message"` - Create branch, stage all changes, and commit with message
- `gt create --ai` - Auto-generate branch name and commit message from changes
- `gt commit create -m "message"` - Create commit on current branch (doesn't create new branch)

**Modifying Existing Branches:**

- `git add` - Stage changes manually, OR
- `gt modify -a` - Stage all changes and amend current commit
- `gt modify -c` - Create new commit instead of amending
- `gt modify -m "message"` - Amend with new commit message
- `gt modify -a -m "message"` - Stage all changes and amend with new message
- `gt submit` - Submit/update pull request

**Common Workflow:**

1. Make code changes
2. **Format code**: Run `npx prettier --write .` to ensure proper formatting
3. `gt modify -a -m "descriptive commit message"` - Stage and amend with message
4. `gt submit` - Update the PR with changes

**Graphite Create Options:**

- `-a, --all`: Stage all changes including untracked files
- `-i, --insert`: Insert branch between current and its child
- `-m, --message`: Specify commit message
- `-p, --patch`: Interactively select changes to stage
- `-u, --update`: Stage updates to tracked files only
- `--ai`: Auto-generate branch name and commit message

**Graphite Modify Options:**

- `-a, --all`: Stage all changes before committing
- `-c, --commit`: Create new commit instead of amending
- `-e, --edit`: Open editor to edit commit message
- `-m, --message`: Specify commit message
- `-u, --update`: Stage updates to tracked files

**Key Differences:**

- `gt create` creates a NEW branch stacked on current branch
- `gt commit create` creates a commit on the CURRENT branch
- `gt modify` modifies the most recent commit on current branch

**Graphite Stacking Best Practices:**

- Break up changes/features into small branches for easier review and integration
- Use `gt create` to stack related changes on top of each other
- Each branch should represent a logical unit of work
- Submit stacked branches as separate PRs that can be reviewed independently
- Use descriptive branch names that reflect the specific change being made

## Documentation Development

### Prerequisites for Documentation Work

Before working with the documentation, build the packages that are imported:

1. **Install dependencies** from the root directory:

   ```bash
   pnpm install
   ```

2. **Build packages** from the root directory:

   ```bash
   pnpm build:js
   ```

   Note: Documentation builds use `build:js` to avoid unnecessary contract compilation. If the build fails due to missing TypeScript dependencies, check individual package devDependencies.

3. **Start docs development server**:
   ```bash
   cd docs
   pnpm dev
   ```

### Changelog Management

**IMPORTANT**: Never directly edit changelog files in the `docs/pages/changelogs/` directory. These files are automatically generated.

**Changelog Source and Generation:**

- **Source files**: Individual package `CHANGELOG.md` files (e.g., `packages/coins/CHANGELOG.md`)
- **Generated files**: Documentation changelog files (e.g., `docs/pages/changelogs/coins.mdx`)
- **Generation script**: `docs/scripts/copy-changelogs.ts`

**The generation script automatically:**

- Copies changelog content from package directories to docs
- Removes the first line (package title)
- Adds proper documentation titles (e.g., "Coins Changelog")
- Converts commit hashes to GitHub links
- Processes multiple package changelogs (coins, coins-sdk, protocol-deployments, etc.)

**Automatic Updates:**

- Changelogs are automatically copied to docs during the version update process
- When `pnpm update-version` runs, it automatically calls `pnpm docs:copy-changelogs`
- This ensures documentation changelogs stay in sync with package changelogs

**Manual Updates (if needed):**

1. Edit the source `CHANGELOG.md` file in the relevant package directory
2. Run `pnpm docs:copy-changelogs` from root directory to manually sync
3. The documentation changelog will be updated

### Common Build Issues

#### Missing TypeScript Dependencies

Some packages may fail during `build:js` if TypeScript is not available as a devDependency:

**Error Pattern**: `tsc: command not found` during tsup build
**Solution**: Add TypeScript as devDependency to the failing package:

```json
{
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
```

This commonly affects packages that use tsup configs with `onSuccess` hooks calling `tsc` directly.

### UML Diagrams

#### Generating UML Diagrams

When creating or updating PlantUML diagrams in the `uml/` directory:

1. **Create/update the .puml file** in `uml/` directory
2. **Generate the SVG** by running:
   ```bash
   cd docs
   pnpm generate-uml
   ```
3. **Reference the generated SVG** in documentation using the path: `public/uml/filename.svg`

#### UML File Locations

- **Source files**: `uml/*.puml` (PlantUML format)
- **Generated files**: `public/uml/*.svg` (SVG format for web display)

#### Example

For a file `uml/my-diagram.puml`, the generated SVG will be at `public/uml/my-diagram.svg` and can be referenced in documentation as:

```markdown
![My Diagram](/uml/my-diagram.svg)
```

Note: Use the `/uml/` path (not `public/uml/`) when referencing diagrams in documentation.

### Writing Guidelines

- **Avoid second person language**: Never use "you", "your", "yours" in documentation. Use third person (e.g., "the user", "developers", "coin creators") or imperative voice (e.g., "Call the function", "Set the parameter") instead.

### Redirects Management

#### When Renaming or Moving Documentation Files

When renaming or moving documentation files, always add redirects to `docs/vercel.json` to prevent broken links:

1. **Add redirect entries** in the `redirects` array
2. **Use permanent redirects** (`"permanent": true`) for renamed pages
3. **Use temporary redirects** (`"permanent": false`) for content that may change

#### Example Redirect Entry

```json
{
  "source": "/coins/contracts/factory",
  "destination": "/coins/contracts/creating-a-coin",
  "permanent": true
}
```

#### Common Redirect Scenarios

- **Page renamed**: Redirect old URL to new URL
- **Page moved**: Redirect old path to new path
- **Page removed**: Redirect to most relevant existing page
- **Section reorganized**: Redirect old structure to new structure

Always test redirects after deployment to ensure they work correctly.

### Documentation Commands

- `pnpm generate-uml` - Generate SVG files from PlantUML source files
- `pnpm dev` - Start development server (from docs directory)
- `pnpm build` - Build documentation site (from docs directory)
