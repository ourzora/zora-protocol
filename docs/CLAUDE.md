# CLAUDE.md - Docs

This file provides guidance to Claude Code when working with the documentation in this directory.

## UML Diagrams

### Generating UML Diagrams

When you create or update PlantUML diagrams in the `uml/` directory:

1. **Create/update the .puml file** in `uml/` directory
2. **Generate the SVG** by running:
   ```bash
   cd docs
   pnpm generate-uml
   ```
3. **Reference the generated SVG** in documentation using the path: `public/uml/filename.svg`

### UML File Locations

- **Source files**: `uml/*.puml` (PlantUML format)
- **Generated files**: `public/uml/*.svg` (SVG format for web display)

### Example

For a file `uml/my-diagram.puml`, the generated SVG will be at `public/uml/my-diagram.svg` and can be referenced in documentation as:

```markdown
![My Diagram](/uml/my-diagram.svg)
```

Note: Use the `/uml/` path (not `public/uml/`) when referencing diagrams in documentation.

## Prerequisites for Docs Development

Before working with the documentation, you need to build the packages that are imported:

1. **Install dependencies** from the root directory:
   ```bash
   cd /Users/danovedzora/source/protocol-clones/zora-protocol-agent-1
   pnpm install
   ```

2. **Build packages** from the root directory:
   ```bash
   pnpm build
   ```
   Note: If the build fails due to missing dependencies (like `tsc`), you may need to install TypeScript globally or ensure all dependencies are properly installed.

3. **Start docs development server**:
   ```bash
   cd docs
   pnpm dev
   ```

## Writing Guidelines

- **Avoid second person language**: Never use "you", "your", "yours" in documentation. Use third person (e.g., "the user", "developers", "coin creators") or imperative voice (e.g., "Call the function", "Set the parameter") instead.

## Redirects Management

### When Renaming or Moving Documentation Files

When renaming or moving documentation files, always add redirects to `docs/vercel.json` to prevent broken links:

1. **Add redirect entries** in the `redirects` array
2. **Use permanent redirects** (`"permanent": true`) for renamed pages
3. **Use temporary redirects** (`"permanent": false`) for content that may change

### Example Redirect Entry

```json
{
  "source": "/coins/contracts/factory",
  "destination": "/coins/contracts/creating-a-coin", 
  "permanent": true
}
```

### Common Redirect Scenarios

- **Page renamed**: Redirect old URL to new URL
- **Page moved**: Redirect old path to new path  
- **Page removed**: Redirect to most relevant existing page
- **Section reorganized**: Redirect old structure to new structure

Always test redirects after deployment to ensure they work correctly.

## Development Commands

- `pnpm generate-uml` - Generate SVG files from PlantUML source files
- `pnpm dev` - Start development server
- `pnpm build` - Build documentation site