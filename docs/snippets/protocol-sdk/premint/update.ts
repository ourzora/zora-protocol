import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";
import { collection, uid } from "./create";

const premintClient = createPremintClient({ chain });

// sign a message to update the premint, then store the update on the Zora Premint API.
const { signAndSubmit } = await premintClient.updatePremint({
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
  account: creatorAccount,
  // the walletClient will be used to sign the message.
  walletClient,
  // if true, the signature will be checked before being submitted.
  checkSignature: true,
});
