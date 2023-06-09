import {
  http,
  createWalletClient,
  createPublicClient,
  encodeFunctionData,
} from "viem";
import { foundry, mainnet } from "viem/chains";
import { describe, it, expect } from "vitest";
import {
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
} from "./wagmiGenerated";
import { AbiParametersToPrimitiveTypes, ExtractAbiFunction } from "abitype";

const multicallAbi = [
  {
    inputs: [
      {
        components: [
          { internalType: "address", name: "target", type: "address" },
          { internalType: "bool", name: "allowFailure", type: "bool" },
          { internalType: "bytes", name: "callData", type: "bytes" },
        ],
        internalType: "struct Multicall3.Call3[]",
        name: "calls",
        type: "tuple[]",
      },
    ],
    name: "aggregate3",
    outputs: [
      {
        components: [
          { internalType: "bool", name: "success", type: "bool" },
          { internalType: "bytes", name: "returnData", type: "bytes" },
        ],
        internalType: "struct Multicall3.Result[]",
        name: "returnData",
        type: "tuple[]",
      },
    ],
    stateMutability: "payable",
    type: "function",
  },
] as const;

const walletClient = createWalletClient({
  chain: foundry,
  transport: http(),
});

export const walletClientWithAccount = createWalletClient({
  chain: foundry,
  transport: http(),
});

const publicClient = createPublicClient({
  chain: foundry,
  transport: http(),
});

type Address = `0x${string}`;

// JSON-RPC Account
const [creatorAccount, ] =
  (await walletClient.getAddresses()) as [Address, Address, Address];

const factoryProxyAddress = zoraCreator1155FactoryImplConfig.address[
  mainnet.id
].toLowerCase() as `0x${string}`;

const multicallAddress =
  "0xcA11bde05977b3631167028862bE2a173976CA11".toLowerCase() as `0x${string}`;

export type Multicall3Array = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof multicallAbi, "aggregate3">["inputs"]
>[0];

const AddressZero = "0x0000000000000000000000000000000000000000";

type CreateTokenParams = {
  fixedPriceStrategyAddress: `0x${string}`;
  maxSupply: bigint;
  nextTokenId: bigint;
  price?: bigint;
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

      const createToken1Params: CreateTokenParams = {
        maxSupply: 100n,
        nextTokenId: 1n,
        tokenURI: "ipfs://token1",
        fixedPriceStrategyAddress: fixedPriceMinterAddress,
        autoSupplyInterval: 10,
        royaltyBPS: 10,
        royaltyRecipient: creatorAccount,
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
      };

      const setupActions = [
        ...constructCreate1155Calls(createToken1Params),
        ...constructCreate1155Calls(createToken2Params),
        ...constructCreate1155Calls(createToken3Params),
      ];

      const createFunctionCall = encodeFunctionData({
        abi: zoraCreator1155FactoryImplConfig.abi,
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
      });

      const multicallArgs: Multicall3Array = [
        {
          target: factoryProxyAddress,
          allowFailure: false,
          callData: createFunctionCall,
        },
      ];

      const multicallHash = await walletClient.writeContract({
        abi: multicallAbi,
        address: multicallAddress,
        functionName: "aggregate3",
        account: creatorAccount,
        args: [multicallArgs],
        value: 0n,
      });

      expect(
        (await publicClient.waitForTransactionReceipt({ hash: multicallHash }))
          .status
      ).toBe("success");
    },
    // 10 second timeout
    10 * 1000
  );
});
