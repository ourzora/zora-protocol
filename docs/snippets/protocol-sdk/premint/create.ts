import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";

const premintClient = createPremintClient({ chain });

// create and sign the premint, the premint and signature will be uploaded to an api to be served later
const { uid, verifyingContract } = await premintClient.createPremint({
  // the walletClient will be used to sign the message.
  walletClient,
  creatorAccount,
  // if true, will validate that the creator is authorized to create premints on the contract.
  checkSignature: true,
  // collection info of collection to create
  collection: {
    contractAdmin: creatorAccount,
    contractName: "Testing Contract",
    contractURI:
      "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
  },
  // token info of token to create
  tokenCreationConfig: {
    tokenURI:
      "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    // address to get create referral reward
    createReferral: "0x5843c8d6007813de3D2313fC55F2Fa1Cbbc394A6",
    // maximum number of tokens that can be minted.
    maxSupply: 50000n,
    // the maximum number of tokens that can be minted to a single address.
    maxTokensPerAddress: 10n,
    // the earliest time the premint can be brought onchain.  0 for immediate.
    mintStart: 0n,
    // the duration of the mint.  0 for infinite.
    mintDuration: 0n,
    // the price in eth per token, for paid mints.  0 for it to be a free mint.
    pricePerToken: 0n,
    // address to receive creator rewards for free mints, or if its a paid mint, the paid mint sale proceeds.
    payoutRecipient: "0x21122518fdABeEb82250799368deA86524651DE4",
  },
});

// the uid of the created premint
console.log(uid);
// the deterministic contract address of the collection that is to be
// created for the premint.
console.log(verifyingContract);

export { uid, verifyingContract as collection };
