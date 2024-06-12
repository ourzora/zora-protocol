import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";
import { collection, uid } from "./create";

const creatorClient = createCreatorClient({ chain });

const { signAndSubmit } = await creatorClient.deletePremint({
  // Premint collection address to delete the premint from
  collection,
  // id of the premint
  uid,
});

// sign and submit the deletion of the Premint
await signAndSubmit({
  account: creatorAccount,
  // the walletClient will be used to sign the message.
  walletClient,
});
