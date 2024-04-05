import { describe, expect } from "vitest";

import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  defaultContractConfig,
  defaultPremintConfigV2,
} from "src/premint/preminter.test";
import {
  mintsEthUnwrapperAndCallerConfig,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155ImplABI,
  zoraMints1155ABI,
  zoraMints1155Address,
  zoraMintsManagerImplABI,
  zoraMintsManagerImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  BaseError,
  ContractFunctionRevertedError,
  Hex,
  PublicClient,
  WalletClient,
  encodeFunctionData,
  parseEther,
} from "viem";
import {
  collectPremintV2WithMintsParams,
  collectWithMintsParams,
  mintWithEthParams,
  permitTransferBatchToManagerAndCallParams,
  mintsBalanceOfAccountParams,
  collectPremintWithMintsTypedDataDefinition,
  CollectMintArguments,
  fixedPriceMinterMinterArguments,
  decodeCallFailedError,
  safeTransferBatchAndUnwrapTypedDataDefinition,
  safeTransferAndUnwrapEthParams,
  safeTransferAndUnwrapTypedDataDefinition,
} from "./mints-contracts";
import { getPremintCollectionAddress } from "src/premint/preminter";
import {
  MintArguments as PremintMintArguments,
  PremintConfigVersion,
} from "src/premint/contract-types";
import { premintTypedDataDefinition } from "src/premint/preminter";
import { zoraSepolia } from "viem/chains";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 7127513,
  anvilChainId: zoraSepolia.id,
});

const getFixedPricedMinter = async ({
  publicClient,
  chainId,
}: {
  publicClient: PublicClient;
  chainId: keyof typeof zoraCreator1155FactoryImplAddress;
}) =>
  await publicClient.readContract({
    abi: zoraCreator1155FactoryImplConfig.abi,
    address: zoraCreator1155FactoryImplAddress[chainId],
    functionName: "fixedPriceMinter",
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

  contractConfig.contractName = "Testing contract for MINTS";

  const contractAddress = await getPremintCollectionAddress({
    collection: contractConfig,
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

const waitForSuccess = async (hash: Hex, publicClient: PublicClient) => {
  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  expect(receipt.status).toBe("success");
};

const collectMINTsWithEth = async ({
  publicClient,
  walletClient,
  chainId,
  collectorAccount,
  quantityToMint,
}: {
  publicClient: PublicClient;
  chainId: keyof typeof zoraMintsManagerImplAddress;
  collectorAccount: Address;
  quantityToMint: bigint;
  walletClient: WalletClient;
}) => {
  const pricePerMint = await publicClient.readContract({
    abi: zoraMintsManagerImplABI,
    address: zoraMintsManagerImplAddress[chainId],
    functionName: "getEthPrice",
  });

  const simulated = await publicClient.simulateContract(
    mintWithEthParams({
      chainId: chainId,
      quantity: quantityToMint,
      recipient: collectorAccount!,
      pricePerMint,
      account: collectorAccount!,
    }),
  );

  await waitForSuccess(
    await walletClient.writeContract(simulated.request),
    publicClient,
  );
  const mintsTokenId = await publicClient.readContract({
    abi: zoraMintsManagerImplABI,
    address: zoraMintsManagerImplAddress[chainId],
    functionName: "mintableEthToken",
  });

  return mintsTokenId;
};

describe("MINTs collecting and redeeming.", () => {
  anvilTest(
    "can collect MINTs with ETH",
    async ({
      viemClients: { testClient, walletClient, publicClient, chain },
    }) => {
      const [collectorAccount] = await walletClient.getAddresses();
      const initialMintsQuantityToMint = 20n;

      await testClient.setBalance({
        address: collectorAccount!,
        value: parseEther("10"),
      });

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      const pricePerMint = await publicClient.readContract({
        abi: zoraMintsManagerImplABI,
        address: zoraMintsManagerImplAddress[chainId],
        functionName: "getEthPrice",
      });

      const simulated = await publicClient.simulateContract(
        mintWithEthParams({
          chainId: chainId,
          quantity: initialMintsQuantityToMint,
          recipient: collectorAccount!,
          pricePerMint,
          account: collectorAccount!,
        }),
      );

      await waitForSuccess(
        await walletClient.writeContract(simulated.request),
        publicClient,
      );

      // check that the balance is correct
      const totalMintsBalance = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      expect(totalMintsBalance).toEqual(initialMintsQuantityToMint);
    },
  );
  anvilTest(
    "can use MINTSs to collect premint and non-premint",
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

      const initialMINTsBalance = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      // 2. Collect some MINTs
      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectMINTsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: initialMintsQuantityToMint,
      });

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: collectorAccount!,
            chainId: chainId,
          }),
        ),
      ).toEqual(initialMINTsBalance + initialMintsQuantityToMint);

      // 3. Use MINTS to collect the premint
      const mintArguments: PremintMintArguments = {
        mintComment: "Hi!",
        mintRecipient: collectorAccount!,
        mintRewardsRecipients: [],
      };

      const firstQuantityToCollect = 4n;

      // 4. Collect Premint using MINT

      const collectPremintSimulated = await publicClient.simulateContract(
        collectPremintV2WithMintsParams({
          tokenIds: [mintsTokenId],
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
        args: [collectorAccount!, mintsTokenId],
      });

      expect(erc1155Balance).toBe(firstQuantityToCollect);

      // 4. Use MINTs to collect from the created contract non-premint.
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
          tokenIds: [mintsTokenId],
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
        args: [collectorAccount!, mintsTokenId],
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
        initialMINTsBalance +
          initialMintsQuantityToMint -
          (firstQuantityToCollect + secondQuantityToCollect),
      );
    },
  );
  anvilTest(
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

      // 2. Collect some MINTs
      const mintsTokenId = await collectMINTsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: 10n,
      });

      // 3. Use MINTS to collect the premint
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
  );
  anvilTest(
    "can use MINTs to gaslessly collect premint",
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

      // 2. Collect some MINTs
      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectMINTsWithEth({
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

      // 3. Use MINTS to collect the premint
      const mintArguments: PremintMintArguments = {
        mintComment: "Hi!",
        mintRecipient: collectorAccount!,
        mintRewardsRecipients: [],
      };

      // 4. Collect Premint using MINT

      // now sign a message to collect.
      // get random integer:
      const nonce = BigInt(Math.round(Math.random() * 1_000_000));

      const blockTime = (await publicClient.getBlock()).timestamp;

      const premintQuantityToCollect = 3n;

      // make signature deadline 10 seconds from now
      const deadline = blockTime + 10n;

      // get typed data to sign, as well as permit to collect with
      const { typedData, permit } = collectPremintWithMintsTypedDataDefinition({
        account: collectorAccount!,
        chainId: chainId,
        mintArguments,
        nonce,
        deadline,
        tokenIds: [mintsTokenId],
        quantities: [premintQuantityToCollect],
        contractCreationConfig: contractConfig,
        premintConfig: premintConfig,
        premintSignature: premintSignature,
      });

      const permitSignature = await walletClient.signTypedData(typedData);

      // now simulate and execute the transaction
      const permitSimulated = await publicClient.simulateContract({
        ...permitTransferBatchToManagerAndCallParams({
          permit,
          chainId: chainId,
          signature: permitSignature,
        }),
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
  );

  anvilTest(
    "can use MINTs to gaslessly collect on legacy 1155 contracts",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [collectorAccount, permitExecutorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      // 1. Collect some MINTs
      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectMINTsWithEth({
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

      // now sign a message to collect.
      let nonce = BigInt(Math.round(Math.random() * 1_000_000));

      const blockTime = (await publicClient.getBlock()).timestamp;

      const quantityToMintOn1155 = 3n;

      // make signature deadline 10 seconds from now
      const deadline = blockTime + 10n;

      const fixedPriceMinter = await getFixedPricedMinter({
        publicClient,
        chainId,
      });

      const tokenId = 1n;

      const minterArguments = fixedPriceMinterMinterArguments({
        mintRecipient: collectorAccount!,
      });

      // this is the external contract that will be called
      const legacy1155Address = "0x2988C3b4F3A823488e4E2d70F23bD66366639b81";

      // this is the external contract funciton that will be called
      const contractCall = encodeFunctionData({
        abi: zoraCreator1155ImplABI,
        functionName: "mint",
        args: [
          fixedPriceMinter,
          tokenId,
          quantityToMintOn1155,
          [],
          minterArguments,
        ],
      });

      // get typed data to sign, as well as permit to collect with
      const { typedData: batchTransferTypeData, permit: bathTransferPermit } =
        safeTransferBatchAndUnwrapTypedDataDefinition({
          from: collectorAccount!,
          chainId: chainId,
          nonce,
          deadline,
          // token ids to unwrap and burn - must be eth based token ids
          tokenIds: [mintsTokenId],
          // quantities to unwrap and burn
          quantities: [quantityToMintOn1155],
          // external address to call
          addressToCall: legacy1155Address,
          // external contract call
          functionToCall: contractCall,
          // value to send to external contract, extra value from mints
          // will be refunded
          valueToSend: parseEther("0.000777") * quantityToMintOn1155,
        });

      const permitBatchSignature = await walletClient.signTypedData(
        batchTransferTypeData,
      );

      // now simulate and execute the transaction
      const permitBatchSimulated = await publicClient.simulateContract({
        ...permitTransferBatchToManagerAndCallParams({
          permit: bathTransferPermit,
          chainId: chainId,
          signature: permitBatchSignature,
        }),
        account: permitExecutorAccount,
      });

      await waitForSuccess(
        await walletClient.writeContract(permitBatchSimulated.request),
        publicClient,
      );

      nonce = BigInt(Math.round(Math.random() * 1_000_000));

      // make non-batch permit and signtarue
      const { typedData: transferTypeData, permit: transferPermit } =
        safeTransferAndUnwrapTypedDataDefinition({
          from: collectorAccount!,
          chainId: chainId,
          nonce,
          deadline,
          // token ids to unwrap and burn - must be eth based token ids
          tokenId: mintsTokenId,
          // quantities to unwrap and burn
          quantity: quantityToMintOn1155,
          // external address to call
          addressToCall: legacy1155Address,
          // external contract call
          functionToCall: contractCall,
          // value to send to external contract, extra value from mints
          // will be refunded
          valueToSend: parseEther("0.000777") * quantityToMintOn1155,
        });

      const permitSignature =
        await walletClient.signTypedData(transferTypeData);

      const permitSimulated = await publicClient.simulateContract({
        abi: zoraMints1155ABI,
        address: zoraMints1155Address[chainId],
        functionName: "permitSafeTransfer",
        args: [transferPermit, permitSignature],
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
      ).toBe(initialMintsBalance - quantityToMintOn1155 * 2n);

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: mintsEthUnwrapperAndCallerConfig.address[chainId],
            chainId: chainId,
          }),
        ),
      ).toBe(0n);

      const tokenBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: legacy1155Address,
        functionName: "balanceOf",
        args: [collectorAccount!, tokenId],
      });

      expect(tokenBalance).toBe(quantityToMintOn1155 * 2n);
    },
  );
});
