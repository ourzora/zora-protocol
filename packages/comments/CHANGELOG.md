# @zoralabs/comments-contracts

## 0.1.1

### Patch Changes

- fbb389583: Bump viem to 2.53.1

  Raise the pinned viem version from 2.22.12 to 2.53.1 across the monorepo to pick up newer chain definitions and support the latest x402 v2 client packages.

## 0.1.0

### Minor Changes

- e4938846: Remove token holding requirement for commenting

  Users can now comment on any coin without holding the token. Non-admin users must still send 1 spark to comment, but token ownership is no longer required. Delegate commenters can still comment with 0 sparks.

## 0.0.3

### Patch Changes

- 719cf7fc: Support for commenting on coin contracts
