import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { useAccount, useChainId, usePublicClient, useSignTypedData } from "wagmi";

const chainId = useChainId();
const publicClient = usePublicClient()!;
const { address: creatorAddress } = useAccount();

const creatorClient = createCreatorClient({ chainId, publicClient });

const {
  // data to sign
  typedDataDefinition,
  // submit will submit the signature and premint to the api
  submit
} = await creatorClient.createPremint({
  // info of the 1155 contract to create.
  contract: {
    // the account that will be the admin of the collection.  
    // Must match the signer of the premint.
    contractAdmin: creatorAddress!,
    contractName: "Testing Contract",
    contractURI:
      "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
  },
  // token info of token to create
  token: {
    tokenURI:
      "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    payoutRecipient: creatorAddress!,
  },
});

const { signTypedData, data: signature } = useSignTypedData();

if (signature) {
  submit({
    signature
  });
}

// when the user clicks to create, sign the typed data
// @noErrors
<button onClick={() => signTypedData(typedDataDefinition)}>Create</button>