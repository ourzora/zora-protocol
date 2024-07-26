import {
  Address,
  hashTypedData,
  keccak256,
  stringToBytes,
  zeroAddress,
} from "viem";
import { zoraSepolia } from "viem/chains";
import { describe, expect } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155ImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155FactoryImplConfig,
  PremintConfigV1,
  TokenCreationConfigV1,
  PremintConfigVersion,
  TokenCreationConfigV2,
  PremintConfigV2,
  PremintMintArguments,
  ContractCreationConfig,
  premintTypedDataDefinition,
  encodePremintConfig,
} from "@zoralabs/protocol-deployments";

import {
  isValidSignature,
  getPremintExecutorAddress,
  getPremintMintCosts,
} from "./preminter";
import { AnvilViemClientsTest, forkUrls, makeAnvilTest } from "src/anvil";
import { privateKeyToAccount } from "viem/accounts";

const erc1271Abi = [
  {
    type: "function",
    name: "isValidSignature",
    inputs: [
      { name: "_hash", type: "bytes32", internalType: "bytes32" },
      { name: "_signature", type: "bytes", internalType: "bytes" },
    ],
    outputs: [{ name: "", type: "bytes4", internalType: "bytes4" }],
    stateMutability: "view",
  },
] as const;

// create token and contract creation config:
export const defaultContractConfig = ({
  contractAdmin,
}: {
  contractAdmin: Address;
}): ContractCreationConfig => ({
  contractAdmin,
  contractURI: "ipfs://asdfasdfasdf",
  contractName: "My fun NFT",
  additionalAdmins: [],
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

async function setupContracts({
  viemClients: { walletClient, testClient, publicClient, chain },
}: AnvilViemClientsTest) {
  // JSON-RPC Account
  const [
    deployerAccount,
    creatorAccount,
    collectorAccount,
    collaboratorAccount,
  ] = (await walletClient.getAddresses()) as [
    Address,
    Address,
    Address,
    Address,
  ];

  // deploy signature minter contract
  await testClient.setBalance({
    address: deployerAccount,
    value: parseEther("10"),
  });

  const fixedPriceMinterAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplConfig.abi,
    address:
      zoraCreator1155FactoryImplAddress[
        chain.id as keyof typeof zoraCreator1155FactoryImplAddress
      ],
    functionName: "fixedPriceMinter",
  });

  return {
    accounts: {
      deployerAccount,
      creatorAccount,
      collectorAccount,
      collaboratorAccount,
    },
    fixedPriceMinterAddress,
  };
}

const zoraSepoliaAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 11974559,
  anvilChainId: zoraSepolia.id,
});

describe("ZoraCreator1155Preminter", () => {
  zoraSepoliaAnvilTest(
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
        functionName: "getContractWithAdditionalAdminsAddress",
        args: [contractConfig],
      });

      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: viemClients.chain.id,
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
        functionName: "getContractWithAdditionalAdminsAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: tokenContract,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: viemClients.chain.id,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V1,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const { recoveredAddress, isAuthorized } = await isValidSignature({
        collection: contractConfig,
        collectionAddress: tokenContract,
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
        functionName: "getContractWithAdditionalAdminsAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: tokenContract,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: viemClients.chain.id,
          premintConfig,
          premintConfigVersion: PremintConfigVersion.V2,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const { recoveredAddress, isAuthorized } = await isValidSignature({
        collection: contractConfig,
        collectionAddress: tokenContract,
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
        functionName: "getContractWithAdditionalAdminsAddress",
        args: [contractConfig],
      });

      // have creator sign the message to create the contract
      // and the token
      const signedMessage = await viemClients.walletClient.signTypedData({
        ...premintTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: viemClients.chain.id,
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
      ).totalCostEth;

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

      const mintArguments: PremintMintArguments = {
        mintComment: "",
        mintRecipient: collectorAccount,
        mintRewardsRecipients: [],
      };

      const firstMinter = collectorAccount;

      // now have the collector execute the first signed message;
      // it should create the contract, the token,
      // and min the quantity to mint tokens to the collector
      // the signature along with contract + token creation
      // parameters are required to call this function
      const mintHash = await viemClients.walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        chain: viemClients.chain,
        address: PREMINTER_ADDRESS,
        args: [
          contractConfig,
          zeroAddress,
          encodePremintConfig({
            premintConfig: premintConfig1,
            premintConfigVersion: PremintConfigVersion.V1,
          }),
          signedMessage,
          quantityToMint,
          mintArguments,
          firstMinter,
          zeroAddress,
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
          chainId: viemClients.chain.id,
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
      ).totalCostEth;

      const simulationResult = await viemClients.publicClient.simulateContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        chain: viemClients.chain,
        address: PREMINTER_ADDRESS,
        args: [
          contractConfig,
          zeroAddress,
          encodePremintConfig({
            premintConfig: premintConfig2,
            premintConfigVersion: PremintConfigVersion.V2,
          }),
          signedMessage2,
          quantityToMint2,
          mintArguments,
          firstMinter,
          zeroAddress,
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
    40 * 1000,
  ),
    zoraSepoliaAnvilTest(
      "can sign a premint from an smart contract account and mint tokens against that premint",
      async ({ viemClients }) => {
        const {
          fixedPriceMinterAddress,
          accounts: { collectorAccount },
        } = await setupContracts({ viemClients });

        // this test shows how to create a premint that is signed by an EOA, but the premint
        // contract admin will be a smart wallet owned by the EOA.
        // contract admin is set as the smart wallet.  Smart wallet owner is the EOA.
        // EOA signs the premint.
        // When calling `premint` smart wallets address must be passed as an argument

        // this was an AA contract that was deployed that has has the owner below as the
        // valid signer. See https://sepolia.explorer.zora.energy/address/0x74F5fAf983d54FEd6D937654Aa4FD258534F2d4B?tab=contract
        // it was deployed via the script `packages/1155-deployments/script/DeploySimpleAA.s.sol`
        const smartWalletAddress = "0x74F5fAf983d54FEd6D937654Aa4FD258534F2d4B";
        const ownerAddress = "0x7c8999dC9a822c1f0Df42023113EDB4FDd543266";
        const ownerPrivateKey =
          "0x02016836a56b71f0d02689e69e326f4f4c1b9057164ef592671cf0d37c8040c0";

        const ownerAccount = privateKeyToAccount(ownerPrivateKey);

        const premintConfig = defaultPremintConfigV2({
          fixedPriceMinter: fixedPriceMinterAddress,
          // we set the creator to the AA contract
          creatorAccount: smartWalletAddress,
        });

        expect(ownerAccount.address).toBe(ownerAddress);

        const contractConfig = defaultContractConfig({
          // for the contract config, we set the smart wallet as the admin
          contractAdmin: smartWalletAddress,
        });

        let contractAddress = await viemClients.publicClient.readContract({
          abi: preminterAbi,
          address: PREMINTER_ADDRESS,
          functionName: "getContractWithAdditionalAdminsAddress",
          args: [contractConfig],
        });

        const typedData = premintTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: viemClients.chain.id,
          premintConfig: premintConfig,
          premintConfigVersion: PremintConfigVersion.V2,
        });

        // have creator sign the message to create the contract
        // and the token
        const signedMessage = await viemClients.walletClient.signTypedData({
          ...typedData,
          account: ownerAccount,
        });

        // sanity check - validate the signature on the smart wallet contract
        const result = await viemClients.publicClient.readContract({
          abi: erc1271Abi,
          address: smartWalletAddress,
          functionName: "isValidSignature",
          args: [hashTypedData(typedData), signedMessage],
        });

        // if is a valid signature, signature should return `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`
        const expectedMagicValue = keccak256(
          stringToBytes("isValidSignature(bytes32,bytes)"),
        ).slice(0, 10);

        expect(result).toBe(expectedMagicValue);

        const quantityToMint = 2n;

        const valueToSend = (
          await getPremintMintCosts({
            publicClient: viemClients.publicClient,
            quantityToMint,
            tokenContract: contractAddress,
            tokenPrice: premintConfig.tokenConfig.pricePerToken,
          })
        ).totalCostEth;

        await viemClients.testClient.setBalance({
          address: collectorAccount,
          value: parseEther("10"),
        });

        const mintArguments: PremintMintArguments = {
          mintComment: "",
          mintRecipient: collectorAccount,
          mintRewardsRecipients: [],
        };

        const firstMinter = collectorAccount;

        // now have the collector execute the first signed message;
        // it should create the contract, the token,
        // and min the quantity to mint tokens to the collector
        // the signature along with contract + token creation
        // parameters are required to call this function
        await viemClients.publicClient.simulateContract({
          abi: preminterAbi,
          functionName: "premint",
          account: collectorAccount,
          chain: viemClients.chain,
          address: PREMINTER_ADDRESS,
          args: [
            contractConfig,
            zeroAddress,
            encodePremintConfig({
              premintConfig: premintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            signedMessage,
            quantityToMint,
            mintArguments,
            firstMinter,
            // we must specify the smart wallet address in the call, so that the 1155 contract
            // knows to have the smart wallet validate the signature
            smartWalletAddress,
          ],
          value: valueToSend,
        });
      },
      40 * 1000,
    ),
    zoraSepoliaAnvilTest(
      "can have collaborators create premints that can be executed on existing contracts",
      async ({ viemClients }) => {
        const {
          fixedPriceMinterAddress,
          accounts: { creatorAccount, collectorAccount, collaboratorAccount },
        } = await setupContracts({ viemClients });

        await viemClients.testClient.setBalance({
          address: collectorAccount,
          value: parseEther("10"),
        });

        // setup contract and token creation parameters
        const premintConfig = defaultPremintConfigV2({
          fixedPriceMinter: fixedPriceMinterAddress,
          creatorAccount,
        });
        // lets make it a random number to not break the existing tests that expect fresh data
        premintConfig.uid = Math.round(Math.random() * 1000000);

        // create a premint config that a collaboratorw ill sign
        const collaboratorPremintConfig = {
          ...premintConfig,
          uid: Math.round(Math.random() * 1000000),
        };

        const contractConfig = defaultContractConfig({
          contractAdmin: creatorAccount,
        });

        // modify contract config to have collaborators
        contractConfig.additionalAdmins = [collaboratorAccount];

        const contractAddress = await viemClients.publicClient.readContract({
          abi: preminterAbi,
          address: PREMINTER_ADDRESS,
          functionName: "getContractWithAdditionalAdminsAddress",
          args: [contractConfig],
        });

        // have creator sign the message to create the contract
        // and the token
        const creatorSignedMessage =
          await viemClients.walletClient.signTypedData({
            ...premintTypedDataDefinition({
              verifyingContract: contractAddress,
              // we need to sign here for the anvil chain, cause thats where it is run on
              chainId: viemClients.chain.id,
              premintConfig: premintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            account: creatorAccount,
          });

        const collaboratorSignedMessage =
          await viemClients.walletClient.signTypedData({
            ...premintTypedDataDefinition({
              verifyingContract: contractAddress,
              // we need to sign here for the anvil chain, cause thats where it is run on
              chainId: viemClients.chain.id,
              premintConfig: collaboratorPremintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            account: collaboratorAccount,
          });

        const quantityToMint = 2n;

        const valueToSend = (
          await getPremintMintCosts({
            publicClient: viemClients.publicClient,
            quantityToMint,
            tokenContract: contractAddress,
            tokenPrice: premintConfig.tokenConfig.pricePerToken,
          })
        ).totalCostEth;

        const mintArguments: PremintMintArguments = {
          mintComment: "",
          mintRecipient: collectorAccount,
          mintRewardsRecipients: [],
        };

        const firstMinter = collectorAccount;

        await viemClients.publicClient.simulateContract({
          abi: preminterAbi,
          functionName: "premint",
          account: collectorAccount,
          chain: viemClients.chain,
          address: PREMINTER_ADDRESS,
          args: [
            contractConfig,
            zeroAddress,
            encodePremintConfig({
              premintConfig: collaboratorPremintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            collaboratorSignedMessage,
            quantityToMint,
            mintArguments,
            firstMinter,
            zeroAddress,
          ],
          value: valueToSend,
        });

        // now have the collector execute collaborators signed message;
        // it should create the contract, the token, and add the collaborator
        // as an admin to the contract along with the original creator
        let tx = await viemClients.walletClient.writeContract({
          abi: preminterAbi,
          functionName: "premint",
          account: collectorAccount,
          chain: viemClients.chain,
          address: PREMINTER_ADDRESS,
          args: [
            contractConfig,
            zeroAddress,
            encodePremintConfig({
              premintConfig: collaboratorPremintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            collaboratorSignedMessage,
            quantityToMint,
            mintArguments,
            firstMinter,
            zeroAddress,
          ],
          value: valueToSend,
        });

        // ensure it succeeded
        expect(
          (
            await viemClients.publicClient.waitForTransactionReceipt({
              hash: tx,
            })
          ).status,
        ).toBe("success");

        tx = await viemClients.walletClient.writeContract({
          abi: preminterAbi,
          functionName: "premint",
          account: collectorAccount,
          chain: viemClients.chain,
          address: PREMINTER_ADDRESS,
          args: [
            contractConfig,
            zeroAddress,
            encodePremintConfig({
              premintConfig: premintConfig,
              premintConfigVersion: PremintConfigVersion.V2,
            }),
            creatorSignedMessage,
            quantityToMint,
            mintArguments,
            firstMinter,
            zeroAddress,
          ],
          value: valueToSend,
        });

        expect(
          (
            await viemClients.publicClient.waitForTransactionReceipt({
              hash: tx,
            })
          ).status,
        ).toBe("success");

        // get balance of second token
        const tokenBalances = await viemClients.publicClient.readContract({
          abi: zoraCreator1155ImplABI,
          address: contractAddress,
          functionName: "balanceOfBatch",
          args: [
            [collectorAccount, collectorAccount],
            [1n, 2n],
          ],
        });

        expect(tokenBalances).toEqual([quantityToMint, quantityToMint]);
      },
      // 10 second timeout
      40 * 1000,
    );
});
