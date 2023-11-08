import { parseEther } from "viem";
import { describe, expect } from "vitest";
import {
  createNew1155Token,
  getTokenIdFromCreateReceipt,
} from "./1155-create-helper";
import { anvilTest } from "src/anvil";

const demoTokenMetadataURI = "ipfs://DUMMY/token.json";
const demoContractMetadataURI = "ipfs://DUMMY/contract.json";

describe("create-helper", () => {
  anvilTest(
    "creates a new contract given arguments",
    async ({ viemClients: { testClient, publicClient, walletClient } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;
      await testClient.setBalance({
        address: creatorAddress,
        value: parseEther("1"),
      });
      const new1155TokenRequest = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAddress,
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
  anvilTest(
    "creates a new contract, than creates a new token on this existing contract",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAccount = addresses[0]!;

      const new1155TokenRequest = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract2",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAccount,
        mintToCreatorCount: 1,
      });
      expect(new1155TokenRequest.contractAddress).to.be.equal(
        "0xb1A8928dF830C21eD682949Aa8A83C1C215194d3",
      );
      expect(new1155TokenRequest.contractExists).to.be.false;
      const hash = await new1155TokenRequest.send(walletClient);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const firstTokenId = getTokenIdFromCreateReceipt(receipt);
      expect(firstTokenId).to.be.equal(1n);
      expect(receipt).not.toBeNull();

      const newTokenOnExistingContract = await createNew1155Token({
        publicClient,
        contract: {
          name: "testContract2",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAccount,
        mintToCreatorCount: 1,
      });
      expect(newTokenOnExistingContract.contractAddress).to.be.equal(
        "0xb1A8928dF830C21eD682949Aa8A83C1C215194d3",
      );
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
