import { mint } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, minterAccount } from "./config";

// prepare the mint transaction, which can be simulated via an rpc with the public client.
const { parameters } = await mint({
  // 1155 contract address
  tokenContract: "0x7aae7e67515A2CbB8585C707Ca6db37BDd3EA839",
  // type of item to mint
  mintType: "721",
  // quantity of tokens to mint
  quantityToMint: 3,
  // optional comment to include with the mint
  mintComment: "My comment",
  // optional address that will receive a mint referral reward
  mintReferral: "0x0C8596Ee50e06Ce710237c9c905D4aB63A132207",
  // account that is to invoke the mint transaction
  minterAccount: minterAccount,
  publicClient,
});

// execute the transaction
await walletClient.writeContract(parameters);
