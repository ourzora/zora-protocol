import { describe, expect } from "vitest";

import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  defaultContractConfig,
  defaultPremintConfigV2,
} from "src/premint/preminter.test";
import {
  zoraCreator1155ImplABI,
  zoraMints1155ABI,
  zoraMints1155Address,
  zoraMintsManagerImplAddress,
  PremintMintArguments,
  premintTypedDataDefinition,
  zoraSparks1155Address,
  zoraSparks1155ABI,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  BaseError,
  ContractFunctionRevertedError,
  WalletClient,
  parseEther,
} from "viem";
import {
  collectPremintV2WithMintsParams,
  collectWithMintsParams,
  mintWithEthParams,
  mintsBalanceOfAccountParams,
  CollectMintArguments,
  decodeCallFailedError,
  makePermitToCollectPremintOrNonPremint,
} from "./sparks-contracts";
import { getPremintCollectionAddress } from "src/premint/preminter";
import { PremintConfigVersion } from "src/premint/contract-types";
import { zora } from "viem/chains";
import {
  fixedPriceMinterMinterArguments,
  getFixedPricedMinter,
} from "src/test-utils";
import { PublicClient } from "src/utils";
import { waitForSuccess } from "src/waitForSuccess";
const sparksMainnetDeployedBlock = 17655716;

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  forkBlockNumber: sparksMainnetDeployedBlock,
  anvilChainId: zora.id,
});

const setupContractUsingPremint = async ({
  walletClient,
  publicClient,
  chainId,
  creatorAccount,
}: {
  walletClient: WalletClient;
  publicClient: PublicClient;
  chainId: keyof typeof zoraMintsManagerImplAddress;
  creatorAccount: Address;
}) => {
  const fixedPriceMinter = await getFixedPricedMinter({
    publicClient,
    chainId,
  });

  const premintConfig = defaultPremintConfigV2({
    fixedPriceMinter,
    creatorAccount: creatorAccount!,
    pricePerToken: 0n,
  });

  const contractConfig = defaultContractConfig({
    contractAdmin: creatorAccount!,
  });

  contractConfig.contractName = "Testing contract for SPARKS";

  const contractAddress = await getPremintCollectionAddress({
    contract: contractConfig,
    publicClient,
  });

  const signature = await walletClient.signTypedData({
    ...premintTypedDataDefinition({
      verifyingContract: contractAddress,
      chainId,
      premintConfig,
      premintConfigVersion: PremintConfigVersion.V2,
    }),
    account: creatorAccount!,
  });

  return {
    premintConfig,
    contractConfig,
    contractAddress,
    signature,
    fixedPriceMinter,
  };
};

const tokenId = 1n;

export const collectSPARKsWithEth = async ({
  pricePerMint,
  publicClient,
  walletClient,
  chainId,
  collectorAccount,
  quantityToMint,
}: {
  pricePerMint: bigint;
  publicClient: PublicClient;
  chainId: keyof typeof zoraMintsManagerImplAddress;
  collectorAccount: Address;
  quantityToMint: bigint;
  walletClient: WalletClient;
}) => {
  const { request } = await publicClient.simulateContract(
    mintWithEthParams({
      tokenId,
      chainId: chainId,
      quantity: quantityToMint,
      recipient: collectorAccount!,
      pricePerMint,
      account: collectorAccount!,
    }),
  );

  await waitForSuccess(await walletClient.writeContract(request), publicClient);

  return tokenId;
};

describe("SPARKs collecting and redeeming.", () => {
  anvilTest(
    "can collect SPARKs with ETH",
    async ({
      viemClients: { testClient, walletClient, publicClient, chain },
    }) => {
      const [collectorAccount] = await walletClient.getAddresses();
      const initialMintsQuantityToMint = 20n;

      await testClient.setBalance({
        address: collectorAccount!,
        value: parseEther("10"),
      });

      const chainId = chain.id as keyof typeof zoraSparks1155Address;

      const pricePerMint = await publicClient.readContract({
        abi: zoraSparks1155ABI,
        address: zoraSparks1155Address[chainId],
        functionName: "tokenPrice",
        args: [tokenId],
      });

      const simulated = await publicClient.simulateContract(
        mintWithEthParams({
          chainId: chainId,
          tokenId,
          quantity: initialMintsQuantityToMint,
          pricePerMint,
          account: collectorAccount!,
        }),
      );

      await waitForSuccess(
        await walletClient.writeContract(simulated.request),
        publicClient,
      );

      // check that the balance is correct
      const totalSparksBalance = await publicClient.readContract({
        abi: zoraSparks1155ABI,
        address: zoraSparks1155Address[chainId],
        functionName: "balanceOfAccount",
        args: [collectorAccount!],
      });

      expect(totalSparksBalance).toEqual(initialMintsQuantityToMint);
    },
    20_000,
  );
  anvilTest.skip(
    "can use SPARKs to collect premint and non-premint",
    async ({
      viemClients: { walletClient, publicClient, testClient, chain },
    }) => {
      const [collectorAccount, creatorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      // 1. Create a premint and contract creation config
      const {
        premintConfig,
        contractConfig,
        contractAddress,
        signature: premintSignature,
        fixedPriceMinter,
      } = await setupContractUsingPremint({
        walletClient,
        publicClient,
        chainId,
        creatorAccount: creatorAccount!,
      });

      await testClient.setBalance({
        address: collectorAccount!,
        value: parseEther("10"),
      });

      const initialSPARKsBalance = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      const tokenPrice = await publicClient.readContract({
        abi: zoraSparks1155ABI,
        address: zoraSparks1155Address[chainId],
        functionName: "tokenPrice",
        args: [tokenId],
      });

      // 2. Collect some SPARKs
      const initialMintsQuantityToMint = 20n;

      await collectSPARKsWithEth({
        chainId,
        collectorAccount: collectorAccount!,
        pricePerMint: tokenPrice,
        publicClient,
        walletClient,
        quantityToMint: initialMintsQuantityToMint,
      });

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: collectorAccount!,
            chainId: chainId,
          }),
        ),
      ).toEqual(initialSPARKsBalance + initialMintsQuantityToMint);

      // 3. Use SPARKS to collect the premint
      const mintArguments: PremintMintArguments = {
        mintComment: "Hi!",
        mintRecipient: collectorAccount!,
        mintRewardsRecipients: [],
      };

      const firstQuantityToCollect = 4n;

      // 4. Collect Premint using SPARK

      const collectPremintSimulated = await publicClient.simulateContract(
        collectPremintV2WithMintsParams({
          tokenIds: [sparksTokenId],
          quantities: [firstQuantityToCollect],
          chainId: chainId,
          contractCreationConfig: contractConfig,
          premintConfig: premintConfig,
          mintArguments,
          premintSignature: premintSignature,
          account: collectorAccount!,
        }),
      );

      await waitForSuccess(
        await walletClient.writeContract(collectPremintSimulated.request),
        publicClient,
      );

      const erc1155Balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount!, sparksTokenId],
      });

      expect(erc1155Balance).toBe(firstQuantityToCollect);

      // 4. Use SPARKs to collect from the created contract non-premint.
      const secondQuantityToCollect = 3n;

      const collectMintArguments: CollectMintArguments = {
        mintComment: "comment!",
        minterArguments: fixedPriceMinterMinterArguments({
          mintRecipient: collectorAccount!,
        }),
        mintRewardsRecipients: [],
      };

      const collectSimulated = await publicClient.simulateContract(
        collectWithMintsParams({
          tokenIds: [sparksTokenId],
          quantities: [secondQuantityToCollect],
          account: collectorAccount!,
          chainId: chainId,
          minter: fixedPriceMinter,
          mintArguments: collectMintArguments,
          zoraCreator1155Contract: contractAddress,
          zoraCreator1155TokenId: 1n,
        }),
      );

      await waitForSuccess(
        await walletClient.writeContract(collectSimulated.request),
        publicClient,
      );

      const erc1155BalanceAfter = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount!, sparksTokenId],
      });

      expect(erc1155BalanceAfter).toBe(
        firstQuantityToCollect + secondQuantityToCollect,
      );

      const totalMintsBalance = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      expect(totalMintsBalance).toBe(
        initialSPARKsBalance +
          initialMintsQuantityToMint -
          (firstQuantityToCollect + secondQuantityToCollect),
      );
    },
    20_000,
  );
  anvilTest.skip(
    "can decode errors from transferBatchToManagerAndCall",
    async ({
      viemClients: { walletClient, publicClient, testClient, chain },
    }) => {
      const [collectorAccount, creatorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      // 1. Create a premint and contract creation config
      const { premintConfig, contractConfig } = await setupContractUsingPremint(
        {
          walletClient,
          publicClient,
          chainId,
          creatorAccount: creatorAccount!,
        },
      );

      await testClient.setBalance({
        address: collectorAccount!,
        value: parseEther("10"),
      });

      // 2. Collect some SPARKs
      const mintsTokenId = await collectSPARKsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: 10n,
      });

      // 3. Use SPARKS to collect the premint
      const mintArguments: PremintMintArguments = {
        mintComment: "",
        mintRecipient: collectorAccount!,
        mintRewardsRecipients: [],
      };

      // 4. Collect Premint using a bad signature
      try {
        await publicClient.simulateContract(
          collectPremintV2WithMintsParams({
            tokenIds: [mintsTokenId],
            quantities: [2n],
            chainId: chainId,
            contractCreationConfig: contractConfig,
            premintConfig: premintConfig,
            mintArguments,
            // put in a bad signature
            premintSignature: "0x",
            account: collectorAccount!,
          }),
        );
      } catch (err) {
        if (err instanceof BaseError) {
          const revertError = err.walk(
            (err) => err instanceof ContractFunctionRevertedError,
          );
          if (revertError instanceof ContractFunctionRevertedError) {
            const errorName = revertError.data?.errorName ?? "";

            if (errorName === "CallFailed") {
              const decodedInternalError = decodeCallFailedError(revertError);

              expect(decodedInternalError.errorName).toEqual(
                "InvalidSignature",
              );
            }
          }
        } else {
          throw err;
        }
      }
    },
    20_000,
  );
  anvilTest.skip(
    "can use SPARKs to gaslessly collect premint",
    async ({
      viemClients: { walletClient, publicClient, testClient, chain },
    }) => {
      const [collectorAccount, creatorAccount, permitExecutorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      // 1. Create a premint and contract creation config
      const {
        premintConfig,
        contractConfig,
        signature: premintSignature,
      } = await setupContractUsingPremint({
        walletClient,
        publicClient,
        chainId,
        creatorAccount: creatorAccount!,
      });

      await testClient.setBalance({
        address: collectorAccount!,
        value: parseEther("10"),
      });

      // 2. Collect some SPARKs
      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectSPARKsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: initialMintsQuantityToMint,
      });

      const initialMintsBalance = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      // 3. Use SPARKS to collect the premint
      const mintArguments: PremintMintArguments = {
        mintComment: "Hi!",
        mintRecipient: collectorAccount!,
        mintRewardsRecipients: [],
      };

      // 4. Collect Premint using SPARK

      // now sign a message to collect.
      // get random integer:
      const nonce = BigInt(Math.round(Math.random() * 1_000_000));

      const blockTime = (await publicClient.getBlock()).timestamp;

      const premintQuantityToCollect = 3n;

      // make signature deadline 10 seconds from now
      const deadline = blockTime + 10n;

      // get typed data to sign, as well as permit to collect with
      const { typedData, permit } = makePermitToCollectPremintOrNonPremint({
        mintsOwner: collectorAccount!,
        chainId,
        deadline,
        tokenIds: [mintsTokenId],
        // this quantity of SPARKs will be used to collect premint
        // and will be burned.  This same quantity is the quantity of
        // premint to collect.
        quantities: [premintQuantityToCollect],
        nonce,
        premint: {
          contractCreationConfig: contractConfig,
          mintArguments,
          premintConfig,
          premintSignature,
        },
      });

      const permitSignature = await walletClient.signTypedData(typedData);

      // now simulate and execute the transaction
      const permitSimulated = await publicClient.simulateContract({
        abi: zoraMints1155ABI,
        address: zoraMints1155Address[chainId],
        functionName: "permitSafeTransferBatch",
        args: [permit, permitSignature],
        account: permitExecutorAccount,
      });

      await waitForSuccess(
        await walletClient.writeContract(permitSimulated.request),
        publicClient,
      );

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: collectorAccount!,
            chainId: chainId,
          }),
        ),
      ).toBe(initialMintsBalance - premintQuantityToCollect);
    },
    20_000,
  );
});
