import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { walletClient, chainId, creatorAccount, publicClient } from "./config";
import { collection, uid } from "./create";

const creatorClient = createCreatorClient({ chainId, publicClient });

const { signAndSubmit } = await creatorClient.updatePremint({
  // the premint collection to update is returned from the `createPremint` call
  collection,
  // the id of the premint to update
  uid,
  // updates to the existing token on the premint
  tokenConfigUpdates: {
    maxTokensPerAddress: 100n,
  },
});

// sign and submit the update to the Premint
await signAndSubmit({
  walletClient,
  account: creatorAccount,
});
