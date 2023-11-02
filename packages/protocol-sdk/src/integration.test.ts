import {
  Address,
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
  parseEther,
} from "viem";
import { foundry } from "viem/chains";
import { describe, it, beforeEach, expect, afterEach } from "vitest";
import {
  createNew1155Token,
  getTokenIdFromCreateReceipt,
} from "./1155-create-helper";

const chain = foundry;

const walletClient = createWalletClient({
  chain,
  transport: http(),
});

const testClient = createTestClient({
  chain,
  mode: "anvil",
  transport: http(),
});

const publicClient = createPublicClient({
  chain,
  transport: http(),
});

const [creatorAccount, minterAccount] = (await walletClient.getAddresses()) as [
  Address,
  Address,
];

const demoTokenMetadataURI = "ipfs://DUMMY/token.json";
const demoContractMetadataURI = "ipfs://DUMMY/contract.json";

describe("integration", () => {
  beforeEach(async () => {
    await testClient.setBalance({
      address: creatorAccount,
      value: parseEther("1"),
    });
  });
  afterEach(() => testClient.reset());

  it("allows for creating an 1155 then minting a token", () => {});
});
