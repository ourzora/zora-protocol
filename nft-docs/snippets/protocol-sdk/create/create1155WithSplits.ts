import { create1155 } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, chainId, creatorAccount } from "./config";
import { SplitV1Client, SplitRecipient } from "@0xsplits/splits-sdk";
import { Address, Chain, HttpTransport, PublicClient } from "viem";
import { contract } from "./data";

/* ==== 1. Create the split ===== */

// setup a splits client
const splitsClient = new SplitV1Client({
  chainId,
  publicClient: publicClient as PublicClient<HttpTransport, Chain>,
  apiConfig: {
    // This is a dummy 0xSplits api key, replace with your own
    apiKey: "123456",
  },
});

// configure the split - the first recipient gets 70% of the payout,
// the second gets 30 %
const splitsConfig: {
  recipients: SplitRecipient[];
  distributorFeePercent: number;
} = {
  recipients: [
    {
      address: "0xDADe31b9CdA249f9C241114356Ba81349Ca920aB",
      percentAllocation: 70,
    },
    {
      address: "0xbC4D657fAbEe03181d07043E00dbC5751800Ee05",
      percentAllocation: 30,
    },
  ],
  distributorFeePercent: 0,
};

// get the deterministic split address, and determine if it has been created or not.
const predicted = await splitsClient.predictImmutableSplitAddress(splitsConfig);

if (!predicted.splitExists) {
  // if the split has not been created, create it by getting the transaction to execute
  // and executing it with the wallet client
  const { data, address } =
    await splitsClient.callData.createSplit(splitsConfig);

  await walletClient.sendTransaction({
    to: address as Address,
    account: creatorAccount,
    data,
  });
}

const splitRecipient = predicted.splitAddress;

/* ==== 2. Create the 1155 with the splits recipient as the payoutRecipient ===== */

const { parameters } = await create1155({
  contract,
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
    payoutRecipient: splitRecipient,
  },
  account: creatorAccount,
  publicClient,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
await walletClient.writeContract(request);
