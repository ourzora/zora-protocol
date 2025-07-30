---
---

Move legacy packages to legacy directory

**Organizational Changes:**
- Moved `@zoralabs/protocol-rewards` package from `packages/` to `legacy/` directory
- Moved `@zoralabs/creator-subgraph` package from `packages/` to `legacy/` directory
- These packages are now considered legacy/deprecated infrastructure
- Existing workspace dependencies will continue to work as workspace references automatically resolve to the new locations
- No breaking changes for consumers as the package functionality remains unchanged

**CI Configuration Updates:**
- Moved protocol-rewards contract testing from `contracts.yml` to `legacy_contracts.yml`
- Updated package path reference from `packages/protocol-rewards` to `legacy/protocol-rewards`
- Legacy contracts now run on `workflow_dispatch` instead of every push