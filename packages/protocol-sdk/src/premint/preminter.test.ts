import { Address, zeroAddress } from "viem";
import { foundry } from "viem/chains";
import { describe, expect } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155ImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155FactoryImplConfig,
} from "@zoralabs/protocol-deployments";

import {
  premintTypedDataDefinition,
  isValidSignature,
  recoverCreatorFromCreatorAttribution,
  getPremintExecutorAddress,
  getPremintMintCosts,
} from "./preminter";
import {
  ContractCreationConfig,
  PremintConfigV1,
  TokenCreationConfigV1,
  PremintConfigVersion,
  TokenCreationConfigV2,
  PremintConfigV2,
  MintArguments,
} from "./contract-types";
import { AnvilViemClientsTest, forkUrls, makeAnvilTest } from "src/anvil";

// create token and contract creation config:
export const defaultContractConfig = ({
  contractAdmin,
}: {
  contractAdmin: Address;
}): ContractCreationConfig => ({
  contractAdmin,
  contractURI: "ipfs://asdfasdfasdf",
  contractName: "My fun NFT",
});

const defaultTokenConfigV1 = (
  fixedPriceMinterAddress: Address,
  creatorAccount: Address,
): TokenCreationConfigV1 => ({
  tokenURI: "ipfs://tokenIpfsId0",
  maxSupply: 100n,
  maxTokensPerAddress: 10n,
  pricePerToken: 0n,
  mintStart: 0n,
  mintDuration: 100n,
  royaltyMintSchedule: 30,
  royaltyBPS: 200,
  royaltyRecipient: creatorAccount,
  fixedPriceMinter: fixedPriceMinterAddress,
});

const defaultTokenConfigV2 = (
  fixedPriceMinterAddress: Address,
  creatorAccount: Address,
  createReferral: Address,
  pricePerToken = 0n,
): TokenCreationConfigV2 => ({
  tokenURI: "ipfs://tokenIpfsId0",
  maxSupply: 100n,
  maxTokensPerAddress: 1000n,
  pricePerToken,
  mintStart: 0n,
  mintDuration: 100n,
  royaltyBPS: 200,
  payoutRecipient: creatorAccount,
  fixedPriceMinter: fixedPriceMinterAddress,
  createReferral,
});

const defaultPremintConfigV1 = ({
  fixedPriceMinter,
  creatorAccount,
}: {
  fixedPriceMinter: Address;
  creatorAccount: Address;
}): PremintConfigV1 => ({
  tokenConfig: defaultTokenConfigV1(fixedPriceMinter, creatorAccount),
  deleted: false,
  uid: 105,
  version: 0,
});

export const defaultPremintConfigV2 = ({
  fixedPriceMinter,
  creatorAccount,
  createReferral = zeroAddress,
  pricePerToken = 0n,
}: {
  fixedPriceMinter: Address;
  creatorAccount: Address;
  createReferral?: Address;
  pricePerToken?: bigint;
}): PremintConfigV2 => ({
  tokenConfig: defaultTokenConfigV2(
    fixedPriceMinter,
    creatorAccount,
    createReferral,
    pricePerToken,
  ),
  deleted: false,
  uid: 106,
  version: 0,
});

const PREMINTER_ADDRESS = getPremintExecutorAddress();

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 1265490,
});

async function setupContracts({
  viemClients: { walletClient, testClient, publicClient },
}: AnvilViemClientsTest) {
  // JSON-RPC Account
  const [deployerAccount, creatorAccount, collectorAccount] =
    (await walletClient.getAddresses()) as [Address, Address, Address, Address];

  // deploy signature minter contract
  await testClient.setBalance({
    address: deployerAccount,
    value: parseEther("10"),
  });

  const fixedPriceMinterAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplConfig.abi,
    address: zoraCreator1155FactoryImplAddress[999],
    functionName: "fixedPriceMinter",
  });

  return {
    accounts: {
      deployerAccount,
      creatorAccount,
      collectorAccount,
    },
    fixedPriceMinterAddress,
  };
}

const zoraSepoliaAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 3118200,
});

describe("ZoraCreator1155Preminter", () => {
  // skip for now - we need to make this work on zora testnet chain too
  anvilTest(
    "can sign on the forked premint contract",
    async ({ viemClients }) => {
      const {
        fixedPriceMinterAddress,
        accounts: { creatorAccount },
      } = await setupContracts({ viemClients });
      const premintConfig = defaultPremintConfigV1({
        fixedPriceMinter: fixedPriceMinterAddress,
        creatorAccount,
      });
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      const preminterAddress = getPremintExecutorAddress();

      const contractAddress = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: 999,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V1,
        }),
        account: creatorAccount,
      });

      console.log({
        creatorAccount,
        signedMessage,
        contractConfig,
        premintConfig,
        contractAddress,
      });
    },
    20 * 1000,
  );
  zoraSepoliaAnvilTest(
    "can sign and recover a v1 premint config signature",
    async ({ viemClients }) => {
      const {
        fixedPriceMinterAddress,
        accounts: { creatorAccount },
      } = await setupContracts({ viemClients });

      const premintConfig = defaultPremintConfigV1({
        fixedPriceMinter: fixedPriceMinterAddress,
        creatorAccount,
      });
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      const tokenContract = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: tokenContract,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: foundry.id,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V1,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const { recoveredAddress, isAuthorized } = await isValidSignature({
        collection: contractConfig,
        chainId: viemClients.publicClient.chain!.id,
        premintConfig,
        premintConfigVersion: PremintConfigVersion.V1,
        publicClient: viemClients.publicClient,
        signature: signedMessage,
      });

      expect(recoveredAddress).to.equal(creatorAccount);
      expect(isAuthorized).toBe(true);

      expect(recoveredAddress).to.equal(creatorAccount);
    },

    20 * 1000,
  );
  zoraSepoliaAnvilTest(
    "can sign and recover a v2 premint config signature",
    async ({ viemClients }) => {
      const {
        fixedPriceMinterAddress,
        accounts: { creatorAccount },
      } = await setupContracts({ viemClients });

      const premintConfig = defaultPremintConfigV2({
        creatorAccount,
        fixedPriceMinter: fixedPriceMinterAddress,
        createReferral: creatorAccount,
      });
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      const tokenContract = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: tokenContract,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: foundry.id,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V2,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const { recoveredAddress, isAuthorized } = await isValidSignature({
        collection: contractConfig,
        chainId: viemClients.publicClient.chain!.id,
        premintConfig,
        premintConfigVersion: PremintConfigVersion.V2,
        publicClient: viemClients.publicClient,
        signature: signedMessage,
      });

      expect(recoveredAddress).to.equal(creatorAccount);
      expect(isAuthorized).toBe(true);

      expect(recoveredAddress).to.equal(creatorAccount);
    },

    20 * 1000,
  );
  zoraSepoliaAnvilTest(
    "can sign and mint multiple tokens",
    async ({ viemClients }) => {
      const {
        fixedPriceMinterAddress,
        accounts: { creatorAccount, collectorAccount },
      } = await setupContracts({ viemClients });
      // setup contract and token creation parameters
      const premintConfig1 = defaultPremintConfigV1({
        fixedPriceMinter: fixedPriceMinterAddress,
        creatorAccount,
      });
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      // lets make it a random number to not break the existing tests that expect fresh data
      premintConfig1.uid = Math.round(Math.random() * 1000000);

      let contractAddress = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // have creator sign the message to create the contract
      // and the token
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: foundry.id,
          premintConfig: premintConfig1,
          premintConfigVersion: PremintConfigVersion.V1,
        }),
        account: creatorAccount,
      });

      const quantityToMint = 2n;

      const valueToSend = (
        await getPremintMintCosts({
          publicClient: viemClients.publicClient,
          quantityToMint,
          tokenContract: contractAddress,
          tokenPrice: premintConfig1.tokenConfig.pricePerToken,
        })
      ).totalCost;

      await viemClients.testClient.setBalance({
        address: collectorAccount,
        value: parseEther("10"),
      });

      // get the premint status - it should not be minted
      let [contractCreated, tokenId] =
        await viemClients.publicClient.readContract({
          abi: preminterAbi,
          address: PREMINTER_ADDRESS,
          functionName: "premintStatus",
          args: [contractAddress, premintConfig1.uid],
        });

      expect(contractCreated).toBe(false);
      expect(tokenId).toBe(0n);

      const mintArguments: MintArguments = {
        mintComment: "",
        mintRecipient: collectorAccount,
        mintRewardsRecipients: [],
      };

      // now have the collector execute the first signed message;
      // it should create the contract, the token,
      // and min the quantity to mint tokens to the collector
      // the signature along with contract + token creation
      // parameters are required to call this function
      const mintHash = await viemClients.walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premintV1",
        account: collectorAccount,
        chain: foundry,
        address: PREMINTER_ADDRESS,
        args: [
          contractConfig,
          premintConfig1,
          signedMessage,
          quantityToMint,
          mintArguments,
        ],
        value: valueToSend,
      });

      // ensure it succeeded
      const receipt = await viemClients.publicClient.waitForTransactionReceipt({
        hash: mintHash,
      });

      expect(receipt.status).toBe("success");

      // fetch the premint token id
      [contractCreated, tokenId] = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "premintStatus",
        args: [contractAddress, premintConfig1.uid],
      });

      expect(contractCreated).toBe(true);
      expect(tokenId).not.toBe(0n);

      // now use what was created, to get the balance from the created contract
      const tokenBalance = await viemClients.publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, tokenId],
      });

      // get token balance - should be amount that was created
      expect(tokenBalance).toBe(quantityToMint);

      const premintConfig2 = defaultPremintConfigV2({
        creatorAccount,
        fixedPriceMinter: fixedPriceMinterAddress,
        createReferral: creatorAccount,
      });

      // sign the message to create the second token
      const signedMessage2 = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: foundry.id,
          premintConfig: premintConfig2,
          premintConfigVersion: PremintConfigVersion.V2,
        }),
        account: creatorAccount,
      });

      const quantityToMint2 = 4n;

      const valueToSend2 = (
        await getPremintMintCosts({
          publicClient: viemClients.publicClient,
          quantityToMint: quantityToMint2,
          tokenContract: contractAddress,
          tokenPrice: premintConfig2.tokenConfig.pricePerToken,
        })
      ).totalCost;

      const simulationResult = await viemClients.publicClient.simulateContract({
        abi: preminterAbi,
        functionName: "premintV2",
        account: collectorAccount,
        chain: foundry,
        address: PREMINTER_ADDRESS,
        args: [
          contractConfig,
          premintConfig2,
          signedMessage2,
          quantityToMint2,
          mintArguments,
        ],
        value: valueToSend2,
      });

      // now have the collector execute the second signed message.
      // it should create a new token against the existing contract
      const mintHash2 = await viemClients.walletClient.writeContract(
        simulationResult.request,
      );

      const premintV2Receipt =
        await viemClients.publicClient.waitForTransactionReceipt({
          hash: mintHash2,
        });

      expect(premintV2Receipt.status).toBe("success");

      // now premint status for the second mint, it should be minted
      [, tokenId] = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "premintStatus",
        args: [contractAddress, premintConfig2.uid],
      });

      expect(tokenId).not.toBe(0n);

      // get balance of second token
      const tokenBalance2 = await viemClients.publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, tokenId],
      });

      expect(tokenBalance2).toBe(quantityToMint2);
    },
    // 10 second timeout
    40 * 1000,
  );

  zoraSepoliaAnvilTest(
    "can decode the CreatorAttribution event",
    async ({ viemClients }) => {
      const {
        fixedPriceMinterAddress,
        accounts: { creatorAccount, collectorAccount },
      } = await setupContracts({ viemClients });
      const premintConfig = defaultPremintConfigV2({
        fixedPriceMinter: fixedPriceMinterAddress,
        creatorAccount,
      });
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      // lets make it a random number to not break the existing tests that expect fresh data
      premintConfig.uid = Math.round(Math.random() * 1000000);

      let contractAddress = await viemClients.publicClient.readContract({
        abi: preminterAbi,
        address: PREMINTER_ADDRESS,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      const signingChainId = foundry.id;

      // have creator sign the message to create the contract
      // and the token
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: signingChainId,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V2,
        }),
        account: creatorAccount,
      });

      const quantityToMint = 2n;

      const valueToSend = (
        await getPremintMintCosts({
          publicClient: viemClients.publicClient,
          quantityToMint,
          tokenContract: contractAddress,
          tokenPrice: premintConfig.tokenConfig.pricePerToken,
        })
      ).totalCost;

      await viemClients.testClient.setBalance({
        address: collectorAccount,
        value: parseEther("10"),
      });

      // now have the collector execute the first signed message;
      // it should create the contract, the token,
      // and min the quantity to mint tokens to the collector
      // the signature along with contract + token creation
      // parameters are required to call this function
      const mintHash = await viemClients.walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premintV2",
        account: collectorAccount,
        chain: foundry,
        address: PREMINTER_ADDRESS,
        args: [
          contractConfig,
          premintConfig,
          signedMessage,
          quantityToMint,
          {
            mintComment: "",
            mintRecipient: collectorAccount,
            mintRewardsRecipients: [],
          },
        ],
        value: valueToSend,
      });

      // ensure it succeeded
      const receipt = await viemClients.publicClient.waitForTransactionReceipt({
        hash: mintHash,
      });

      expect(receipt.status).toBe("success");

      // get the CreatorAttribution event from the erc1155 contract:
      const topics = await viemClients.publicClient.getContractEvents({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        eventName: "CreatorAttribution",
      });

      expect(topics.length).toBe(1);

      const creatorAttributionEvent = topics[0]!;

      const { creator: creatorFromEvent } = creatorAttributionEvent.args;

      const recoveredSigner = await recoverCreatorFromCreatorAttribution({
        creatorAttribution: creatorAttributionEvent.args,
        chainId: signingChainId,
        tokenContract: contractAddress,
      });

      expect(creatorFromEvent).toBe(creatorAccount);
      expect(recoveredSigner).toBe(creatorFromEvent);
    },
  );
});
