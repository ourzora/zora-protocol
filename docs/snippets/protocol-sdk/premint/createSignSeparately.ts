import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { walletClient, chain, creatorAccount } from "./config";

const creatorClient = createCreatorClient({ chain });

const collection = {
  // the account that will be the admin of the collection.  Must match the signer of the premint.
  contractAdmin: creatorAccount,
  contractName: "Testing Contract",
  contractURI:
    "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
};

// create and sign the Premint, the Premint and signature will be uploaded to an api to be served later
const {
  // used to sign and submit the premint to the Zora Premint API
  typedDataDefinition, // [!code focus]
  submit, // [!code focus]
} = await creatorClient.createPremint({
  collection,
  // token info of token to create
  tokenCreationConfig: {
    tokenURI:
      "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",

    payoutRecipient: creatorAccount,
  },
});

// the signature can be signed using the typedDataDefinition with `walletClient.signTypedData`
const signature = await walletClient.signTypedData({
  // [!code focus]
  ...typedDataDefinition, // [!code focus]
  account: creatorAccount, // [!code focus]
});

// the signature can be submitted using the returned submit function
await submit({
  // [!code focus]
  signature, // [!code focus]
}); // [!code focus]
