# Protocol Deployments Codegen

This is an internal package meant to generate code for use in `protocol-deployments`.
It pulls in abis and addresses from relevant packages in the monorepo, and bundles them
into a file in `protocol-deployments`. The reason to have it as a separate package
is to avoid `protocol-deployments` having dependencies to internal/non-published packages.
