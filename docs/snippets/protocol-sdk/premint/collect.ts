import { createPremintClient } from "@zoralabs/protocol-sdk";
import { walletClient, publicClient, chain, minterAccount } from "./config";
import { collection, uid } from "./create";

const premintClient = createPremintClient({ chain });

// get parameters to mint a premint, which can be used to simulate and submit the transaction
const simulateContractParameters = await premintClient.makeMintParameters({
  // the account to execute the transaction
  minterAccount,
  // the premint contract to mint the token on
  tokenContract: collection,
  // the uid of the premint to mint
  uid,
  mintArguments: {
    // how many tokens to mint
    quantityToMint: 1,
    // Comment to attach to the mint
    mintComment: "Mint comment",
    // optional: account to receive the minted tokens.  if not set, defaults to
    // the `minterAccount`
    mintRecipient: "0xf0b64c556a01cb5be3fce68312618b13a78ef0aa",
    // optional: account to receive the mint referral reward.
    mintReferral: "0x21122518fdABeEb82250799368deA86524651DE4",
  },
});

// simulate the transaction and get any validation errors
const { request } = await publicClient.simulateContract(
  simulateContractParameters,
);

// submit the transaction to the network
const txHash = await walletClient.writeContract(request);

// wait for the transaction to be complete
const receipt = await publicClient.waitForTransactionReceipt({
  hash: txHash,
});

const { urls } = await premintClient.getDataFromPremintReceipt(receipt);

// block explorer url:
console.log(urls.explorer);
// collect url:
console.log(urls.zoraCollect);
// manage url:
console.log(urls.zoraManage);
