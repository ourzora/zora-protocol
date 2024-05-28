import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";
import { collection, uid } from "./create";

const premintClient = createPremintClient({ chain });

// create a call to sign and submit a deletion of a premint
const { signAndSubmit } = await premintClient.deletePremint({
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
  // if true, the signature will be checked before being submitted.
  checkSignature: true,
});
