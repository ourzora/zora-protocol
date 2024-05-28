import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";
import { collection, uid } from "./create";

const premintClient = createPremintClient({ chain });

// sign a message to update the premint, then store the update on the Zora Premint API.
await premintClient.updatePremint({
  // the premint collection to update is returned from the `createPremint` call
  collection,
  // the id of the premint to update
  uid,
  // WalletClient signs the message
  walletClient,
  // account to sign the message to update the premint
  account: creatorAccount,
  // Updated token information - this will be merged on top of the existing premint.
  tokenConfigUpdates: {
    maxTokensPerAddress: 100n,
  },
});
