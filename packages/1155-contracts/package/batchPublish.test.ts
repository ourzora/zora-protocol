import {
  http,
  createWalletClient,
  createPublicClient,
  encodeFunctionData,
  TransactionReceipt,
  decodeEventLog,
  encodeAbiParameters,
  parseEther,
  createTestClient,
} from "viem";
import { foundry, zora } from "viem/chains";
import { describe, it, expect } from "vitest";
import {
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
} from "./wagmiGenerated";

const walletClient = createWalletClient({
  chain: foundry,
  transport: http(),
});

export const walletClientWithAccount = createWalletClient({
  chain: foundry,
  transport: http(),
});

const testClient = createTestClient({
  chain: foundry,
  mode: "anvil",
  transport: http(),
});

const publicClient = createPublicClient({
  chain: foundry,
  transport: http(),
});

type Address = `0x${string}`;

// JSON-RPC Account
const [creatorAccount, collectorAccount] =
  (await walletClient.getAddresses()) as [Address, Address, Address];

const factoryProxyAddress = zoraCreator1155FactoryImplConfig.address[
  zora.id
].toLowerCase() as `0x${string}`;

const AddressZero = "0x0000000000000000000000000000000000000000";

type CreateTokenParams = {
  fixedPriceStrategyAddress: `0x${string}`;
  maxSupply: bigint;
  nextTokenId: bigint;
  price: bigint;
  saleEnd?: bigint;
  saleStart?: bigint;
  mintLimit?: bigint;
  tokenURI: string;
  royaltyBPS: number;
  royaltyRecipient: `0x${string}`;
  autoSupplyInterval: number;
};

function constructCreate1155Calls({
  fixedPriceStrategyAddress,
  maxSupply,
  mintLimit,
  nextTokenId,
  price,
  saleEnd,
  saleStart,
  tokenURI,
  royaltyBPS,
  royaltyRecipient,
  autoSupplyInterval,
}: CreateTokenParams): `0x${string}`[] {
  if (!royaltyRecipient) {
    royaltyRecipient = AddressZero;
    autoSupplyInterval = 0;
  }
  const verifyTokenIdExpected = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "assumeLastTokenIdMatches",
    args: [nextTokenId - 1n],
  });

  const setupNewToken = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "setupNewToken",
    args: [tokenURI, maxSupply],
  });

  let royaltyConfig = null;
  if (royaltyBPS > 0 && royaltyRecipient != AddressZero) {
    royaltyConfig = encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "updateRoyaltiesForToken",
      args: [
        nextTokenId,
        {
          royaltyBPS,
          royaltyRecipient,
          royaltyMintSchedule: autoSupplyInterval,
        },
      ],
    });
  }

  const contractCalls = [
    verifyTokenIdExpected,
    setupNewToken,
    royaltyConfig,
  ].filter((item) => item !== null) as `0x${string}`[];

  if (typeof price !== "undefined") {
    const fixedPriceApproval = encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "addPermission",
      args: [
        nextTokenId,
        fixedPriceStrategyAddress,
        2n ** 2n, // PERMISSION_BIT_MINTER
      ],
    });

    const saleData = encodeFunctionData({
      abi: zoraCreatorFixedPriceSaleStrategyABI,
      functionName: "setSale",
      args: [
        nextTokenId,
        {
          pricePerToken: price,
          saleStart: saleStart || 0n,
          saleEnd: saleEnd || 0n,
          maxTokensPerAddress: mintLimit || 0n,
          fundsRecipient: AddressZero,
        },
      ],
    });

    const callSale = encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "callSale",
      args: [nextTokenId, fixedPriceStrategyAddress, saleData],
    });

    return [...contractCalls, fixedPriceApproval, callSale] as `0x${string}`[];
  }

  return contractCalls;
}

function parseCreate1155Receipt(receipt: TransactionReceipt): {
  contractAddress?: `0x${string}`;
  tokenId?: bigint;
} {
  const parsedLog = receipt.logs
    .map((log) => {
      try {
        return decodeEventLog({
          abi: zoraCreator1155ImplABI,
          ...log,
        });
      } catch (e) {
        return null;
      }
    })
    .filter(Boolean);

  const updatedTokenEvents = parsedLog.filter(
    (log) => log?.eventName === "UpdatedToken"
  );
  const lastUpdatedTokenEvent =
    updatedTokenEvents[updatedTokenEvents.length - 1];

  let tokenId;
  let contractAddress;

  // @ts-ignore
  if (lastUpdatedTokenEvent?.args?.tokenId) {
    // @ts-ignore
    tokenId = lastUpdatedTokenEvent?.args?.tokenId as bigint;
  }

  // @ts-ignore
  if (receipt.logs?.[0].address) {
    contractAddress = receipt.logs?.[0].address as `0x${string}`;
  }

  return { tokenId, contractAddress };
}

describe("ZoraCreator1155Preminter", () => {
  it(
    "can batch publish tokens",
    async () => {
      const fixedPriceMinterAddress = await publicClient.readContract({
        abi: zoraCreator1155FactoryImplConfig.abi,
        address: factoryProxyAddress,
        functionName: "fixedPriceMinter",
      });

      const contractAdmin = creatorAccount;
      const contractUri = "ipfs://contracturl";
      const contractName = "my contract";

      // setup token creation parameters, assuming that
      // they have auto incrementing ids
      const createToken1Params: CreateTokenParams = {
        maxSupply: 100n,
        mintLimit: 100n,
        nextTokenId: 1n,
        tokenURI: "ipfs://token1",
        fixedPriceStrategyAddress: fixedPriceMinterAddress,
        autoSupplyInterval: 10,
        price: parseEther("0.05"),
        royaltyBPS: 10,
        royaltyRecipient: creatorAccount,
        saleStart: 0n,
        saleEnd: 10000000000000n,
      };

      const createToken2Params: CreateTokenParams = {
        ...createToken1Params,
        tokenURI: "ipfs://token2",
        nextTokenId: 2n,
      };

      const createToken3Params: CreateTokenParams = {
        ...createToken1Params,
        tokenURI: "ipfs://token3",
        nextTokenId: 3n,
        price: parseEther("0.0001"),
      };

      // build setup actions to create tokens when contract is created
      const setupActions = [
        ...constructCreate1155Calls(createToken1Params),
        ...constructCreate1155Calls(createToken2Params),
        ...constructCreate1155Calls(createToken3Params),
      ];

      // have the factory create the contract
      const createContractCall = await walletClient.writeContract({
        abi: zoraCreator1155FactoryImplConfig.abi,
        address: zoraCreator1155FactoryImplConfig.address[zora.id],
        functionName: "createContract",
        args: [
          contractUri,
          contractName,
          {
            royaltyBPS: 10,
            royaltyMintSchedule: 5,
            royaltyRecipient: creatorAccount,
          },
          contractAdmin,
          setupActions,
        ],
        account: creatorAccount,
      });

      const receipt = await publicClient.waitForTransactionReceipt({
        hash: createContractCall,
      });

      expect(receipt.status).toBe("success");

      // parse the receipt to get the contract address and last token id
      const { contractAddress, tokenId: lastTokenId } =
        parseCreate1155Receipt(receipt);

      // now try to mint a token
      const quantityToMint = 2n;

      const encodedParams = encodeAbiParameters(
        [{ type: "address", name: "address" }],
        [collectorAccount]
      );

      const zoraMintFee = parseEther("0.000777");

      const valueToSend =
        (BigInt(zoraMintFee) + createToken3Params.price) * quantityToMint;

      // make sure the collector has enough balance
      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

      const mintCall = await walletClient.writeContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress!,
        functionName: "mint",
        account: collectorAccount,
        args: [
          fixedPriceMinterAddress,
          lastTokenId!,
          quantityToMint,
          encodedParams,
        ],
        value: valueToSend,
      });

      expect(
        (await publicClient.waitForTransactionReceipt({ hash: mintCall }))
          .status
      ).toBe("success");

      // check balance of token
      const tokenBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress!,
        functionName: "balanceOf",
        args: [collectorAccount, lastTokenId!],
      });

      expect(tokenBalance).toBe(quantityToMint);
    },
    // 10 second timeout
    10 * 1000
  );
});
