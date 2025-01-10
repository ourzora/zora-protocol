```
 ________   ______   _______    ______         _______    ______    ______    ______
/        | /      \ /       \  /      \       /       \  /      \  /      \  /      \
$$$$$$$$/ /$$$$$$  |$$$$$$$  |/$$$$$$  |      $$$$$$$  |/$$$$$$  |/$$$$$$  |/$$$$$$  |
    /$$/  $$ |  $$ |$$ |__$$ |$$ |__$$ |      $$ |  $$ |$$ |  $$ |$$ |  $$/ $$ \__$$/
   /$$/   $$ |  $$ |$$    $$< $$    $$ |      $$ |  $$ |$$ |  $$ |$$ |      $$      \
  /$$/    $$ |  $$ |$$$$$$$  |$$$$$$$$ |      $$ |  $$ |$$ |  $$ |$$ |   __  $$$$$$  |
 /$$/____ $$ \__$$ |$$ |  $$ |$$ |  $$ |      $$ |__$$ |$$ \__$$ |$$ \__/  |/  \__$$ |
/$$      |$$    $$/ $$ |  $$ |$$ |  $$ |      $$    $$/ $$    $$/ $$    $$/ $$    $$/
$$$$$$$$/  $$$$$$/  $$/   $$/ $$/   $$/       $$$$$$$/   $$$$$$/   $$$$$$/   $$$$$$/
```

[Live Docs Website](https://docs.zora.co/)

The Zora Docs site contains documentation on Zora contracts, SDKs, and the Zora Network.

It is built on the [vocs](https://vocs.dev) framework.

## Development Setup

Before running the dev server, from the root of the monorepo:

```bash
pnpm run build
```

Then, from the `docs` directory, start the dev server:

```bash
pnpm run dev
```

## Generating UML Diagrams

The documentation includes UML diagrams generated from PlantUML source files. To generate these diagrams:

1. Ensure you have Docker installed and running (used for PlantUML generation)

2. PlantUML source files are located in the `docs/uml` directory with `.puml` extension

3. Generate the diagrams by running:

```bash
pnpm run generate-uml
```

This will:

- Process all `.puml` files in the `docs/uml` directory
- Generate SVG diagrams in `public/uml`
- Use Docker to handle loading of the PlantUML server

The generated diagrams can be referenced in documentation using:

```markdown
![Diagram Name](/uml/diagram-name.svg)
```
