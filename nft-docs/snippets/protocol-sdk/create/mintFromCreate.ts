import { createNew1155Token } from "@zoralabs/protocol-sdk";
import {
  publicClient,
  walletClient,
  creatorAccount,
  minterAccount,
} from "./config";
import { contractAddress } from "./createNewContract";

const {
  parameters: createParameters,
  prepareMint, // [!code hl]
} = await createNew1155Token({
  // by providing a contract address, the token will be created on an existing contract
  // at that address
  contractAddress,
  token: {
    // token metadata uri
    tokenMetadataURI: "ipfs://DUMMY/token.json",
  },
  // account to execute the transaction (the creator)
  account: creatorAccount,
  chainId: publicClient.chain.id,
});

const { request } = await publicClient.simulateContract(createParameters);

// execute the transaction
const hash = await walletClient.writeContract(request);
// wait for the response
const createReceipt = await publicClient.waitForTransactionReceipt({ hash });

if (createReceipt.status !== "success") {
  throw new Error("create failed");
}

// the create function returns an async prepareMint function, which
// enables a mint call to be created on the token after it has been created.
// Note this can only be executed after the token has been brought onchain.
const { parameters: mintParams } = await prepareMint({
  quantityToMint: 2n,
  minterAccount,
});

// execute the mint transaction
const mintHash = await walletClient.writeContract(mintParams);

const mintReceipt = await publicClient.waitForTransactionReceipt({
  hash: mintHash,
});

if (mintReceipt.status !== "success") {
  throw new Error("mint failed");
}
