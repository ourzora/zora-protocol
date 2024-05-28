import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";
import { collection, uid } from "./create";

const premintClient = createPremintClient({ chain });

// sign a message to delete the premint, and store the deletion on the Zora Premint API.
await premintClient.deletePremint({
  // Premint collection address to delete the premint from
  collection,
  // id of the premint
  uid,
  // WalletClient doing the signature
  walletClient,
  // account to sign the deletion
  account: creatorAccount,
});
