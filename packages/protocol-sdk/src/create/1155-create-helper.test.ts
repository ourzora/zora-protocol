import { parseEther } from "viem";
import { describe, expect } from "vitest";
import {
  create1155CreatorClient,
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
      const creatorClient = create1155CreatorClient({
        publicClient: publicClient,
      });
      const { request } = await creatorClient.createNew1155Token({
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAddress,
        mintToCreatorCount: 1,
      });
      const { request: simulationResponse } =
        await publicClient.simulateContract(request);
      const hash = await walletClient.writeContract(simulationResponse);
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

      const creatorClient = create1155CreatorClient({
        publicClient: publicClient,
      });

      const { request, contractAddress, contractExists } =
        await creatorClient.createNew1155Token({
          contract: {
            name: "testContract2",
            uri: demoContractMetadataURI,
          },
          tokenMetadataURI: demoTokenMetadataURI,
          account: creatorAccount,
          mintToCreatorCount: 1,
        });
      expect(contractAddress).to.be.equal(
        "0xb1A8928dF830C21eD682949Aa8A83C1C215194d3",
      );
      expect(contractExists).to.be.false;
      const { request: simulateResponse } =
        await publicClient.simulateContract(request);
      const hash = await walletClient.writeContract(simulateResponse);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const firstTokenId = getTokenIdFromCreateReceipt(receipt);
      expect(firstTokenId).to.be.equal(1n);
      expect(receipt).not.toBeNull();

      const newTokenOnExistingContract = await creatorClient.createNew1155Token(
        {
          contract: {
            name: "testContract2",
            uri: demoContractMetadataURI,
          },
          tokenMetadataURI: demoTokenMetadataURI,
          account: creatorAccount,
          mintToCreatorCount: 1,
        },
      );
      expect(newTokenOnExistingContract.contractAddress).to.be.equal(
        "0xb1A8928dF830C21eD682949Aa8A83C1C215194d3",
      );
      expect(newTokenOnExistingContract.contractExists).to.be.true;
      const { request: simulateRequest } = await publicClient.simulateContract(
        newTokenOnExistingContract.request,
      );
      const newHash = await walletClient.writeContract(simulateRequest);
      const newReceipt = await publicClient.waitForTransactionReceipt({
        hash: newHash,
      });
      const tokenId = getTokenIdFromCreateReceipt(newReceipt);
      expect(tokenId).to.be.equal(2n);
      expect(newReceipt).not.toBeNull();
    },
    20 * 1000,
  );
  anvilTest(
    "creates a new token with a create referral address",
    async ({ viemClients: { testClient, publicClient, walletClient } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;
      await testClient.setBalance({
        address: creatorAddress,
        value: parseEther("1"),
      });
      const creatorClient = create1155CreatorClient({
        publicClient: publicClient,
      });
      const { request } = await creatorClient.createNew1155Token({
        contract: {
          name: "testContract",
          uri: demoContractMetadataURI,
        },
        tokenMetadataURI: demoTokenMetadataURI,
        account: creatorAddress,
        mintToCreatorCount: 1,
        createReferral: creatorAddress,
      });
      const { request: simulationResponse } =
        await publicClient.simulateContract(request);
      const hash = await walletClient.writeContract(simulationResponse);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt).not.toBeNull();
      console.log(receipt);
      expect(receipt.to).to.equal("0xa72724cc3dcef210141a1b84c61824074151dc99");
      expect(getTokenIdFromCreateReceipt(receipt)).to.be.equal(2n);
    },
    20 * 1000,
  );
});
