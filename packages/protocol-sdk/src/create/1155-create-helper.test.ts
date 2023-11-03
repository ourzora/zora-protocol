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

const [creatorAccount] = (await walletClient.getAddresses()) as [Address];

const demoTokenMetadataURI = "ipfs://DUMMY/token.json";
const demoContractMetadataURI = "ipfs://DUMMY/contract.json";

describe("create-helper", () => {
  beforeEach(async () => {
    await testClient.setBalance({
      address: creatorAccount,
      value: parseEther("1"),
    });
  });
  afterEach(() => testClient.reset());

  it(
    "creates a new contract given arguments",
    async () => {
      const new1155TokenRequest = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAccount,
        mintToCreatorCount: 1,
      });
      const hash = await new1155TokenRequest.send(walletClient);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt).not.toBeNull();
      expect(receipt.to).to.equal("0x777777c338d93e2c7adf08d102d45ca7cc4ed021");
      expect(getTokenIdFromCreateReceipt(receipt)).to.be.equal(1n);
    },
    20 * 1000,
  );
  it(
    "creates a new contract, than creates a new token on this existing contract",
    async () => {
      const new1155TokenRequest = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAccount,
        mintToCreatorCount: 1,
      });
      expect(new1155TokenRequest.contractAddress).to.be.equal('0xA72724cC3DcEF210141a1B84C61824074151Dc99');
      expect(new1155TokenRequest.contractExists).to.be.false;
      const hash = await new1155TokenRequest.send(walletClient);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const firstTokenId = getTokenIdFromCreateReceipt(receipt);
      expect(firstTokenId).to.be.equal(1n);
      expect(receipt).not.toBeNull();

      const newTokenOnExistingContract = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAccount,
        mintToCreatorCount: 1,
      });
      expect(newTokenOnExistingContract.contractAddress).to.be.equal('0xA72724cC3DcEF210141a1B84C61824074151Dc99');
      expect(newTokenOnExistingContract.contractExists).to.be.true;
      const newHash = await newTokenOnExistingContract.send(walletClient);
      const newReceipt = await publicClient.waitForTransactionReceipt({
        hash: newHash,
      });
      const tokenId = getTokenIdFromCreateReceipt(newReceipt);
      expect(tokenId).to.be.equal(2n);
      expect(newReceipt).not.toBeNull();
    },
    20 * 1000,
  );
});
