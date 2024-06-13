import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { useChainId, usePublicClient, useSignTypedData } from "wagmi";

const chainId = useChainId();
const publicClient = usePublicClient()!;

const creatorClient = createCreatorClient({ chainId, publicClient });

const creatorAccount = "0xf69fEc6d858c77e969509843852178bd24CAd2B6";

const {
  // the premint that is to be created
  premintConfig,
  // deterministic collection address of the premint
  collectionAddress,
  typedDataDefinition,
  submit,
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

    payoutRecipient: creatorAccount,
  },
});

// sign the new premint, and submit it to the Zora Premint API
const { signTypedData, data: signature } = useSignTypedData();

signTypedData(typedDataDefinition);

if (signature) {
  submit({
    signature,
  });
}

export const uid = premintConfig.uid;
export const collection = collectionAddress;
