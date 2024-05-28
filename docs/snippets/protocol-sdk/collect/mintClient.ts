import { createMintClient } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, chain, account } from "./config";
import {
  tokenAddress,
  tokenId,
  mintToAddress,
  quantityToMint,
  mintComment,
  mintReferral,
} from "./data";

const mintClient = createMintClient({ chain });

// prepare the mint transaction, which can be simulated via an rpc with the public client.
const prepared = await mintClient.makePrepareMintTokenParams({
  // 1155 contract address
  tokenAddress,
  tokenId,
  mintArguments: {
    // address that will receive the minted tokens
    mintToAddress,
    // quantity of tokens to mint
    quantityToMint,
    // optional comment to include with the mint
    mintComment,
    // optional address that will receive a mint referral reward
    mintReferral,
  },
  // account that is to invoke the mint transaction
  minterAccount: account,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(prepared);

// execute the transaction
const hash = await walletClient.writeContract(request);
// wait for the response
const receipt = await publicClient.waitForTransactionReceipt({ hash });

if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
