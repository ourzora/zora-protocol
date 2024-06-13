import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { walletClient, chainId, publicClient, creatorAccount } from "./config";

const creatorClient = createCreatorClient({ chainId, publicClient });

// create and sign the Premint, the Premint and signature will be uploaded to an api to be served later
const {
  // used to sign and submit the premint to the Zora Premint API
  signAndSubmit,
} = await creatorClient.createPremint({
  // collection info of collection to create.  The combination of these fields will determine the
  // deterministic collection address.
  contract: {
    // the account that will be the admin of the collection.  Must match the signer of the premint.
    contractAdmin: creatorAccount,
    contractName: "Testing Contract",
    contractURI:
      "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
  },
  // token info of token to create
  token: {
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
    payoutRecipient: creatorAccount,
  },
});

// sign the new premint, and submit it to the Zora Premint API
await signAndSubmit({
  // account to sign the premint
  account: creatorAccount,
  // the walletClient will be used to sign the message.
  walletClient,
  // if true, the signature will be checked before being submitted.
  // this includes validating that the signer is authorized to create the premint.
  checkSignature: true,
});
