import {
  createTestClient,
  http,
  createWalletClient,
  createPublicClient,
  keccak256,
  Hex,
  concat,
  recoverAddress,
  hashDomain,
} from "viem";
import { foundry, zora } from "viem/chains";
import { describe, it, beforeEach, expect, afterEach } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155PremintExecutorImplAddress as zoraCreator1155PremintExecutorAddress,
  zoraCreator1155ImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155FactoryImplConfig,
} from "@zoralabs/protocol-deployments";

import {
  ContractCreationConfig,
  PremintConfig,
  TokenCreationConfig,
  preminterTypedDataDefinition,
} from "./preminter";

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
const [deployerAccount, creatorAccount, collectorAccount] =
  (await walletClient.getAddresses()) as [Address, Address, Address, Address];

type TestContext = {
  preminterAddress: `0x${string}`;
  forkedChainId: keyof typeof zoraCreator1155FactoryImplAddress;
  anvilChainId: number;
  zoraMintFee: bigint;
  fixedPriceMinterAddress: Address;
};

// create token and contract creation config:
const defaultContractConfig = ({
  contractAdmin,
}: {
  contractAdmin: Address;
}): ContractCreationConfig => ({
  contractAdmin,
  contractURI: "ipfs://asdfasdfasdf",
  contractName: "My fun NFT",
});

const defaultTokenConfig = (
  fixedPriceMinterAddress: Address,
): TokenCreationConfig => ({
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

const defaultPremintConfig = (fixedPriceMinter: Address): PremintConfig => ({
  tokenConfig: defaultTokenConfig(fixedPriceMinter),
  deleted: false,
  uid: 105,
  version: 0,
});

describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther("10"),
    });

    ctx.forkedChainId = zora.id;
    ctx.anvilChainId = foundry.id;

    ctx.fixedPriceMinterAddress = await publicClient.readContract({
      abi: zoraCreator1155FactoryImplConfig.abi,
      address: zoraCreator1155FactoryImplAddress[ctx.forkedChainId],
      functionName: "fixedPriceMinter",
    });
    ctx.zoraMintFee = parseEther("0.000777");

    ctx.preminterAddress =
      zoraCreator1155PremintExecutorAddress[ctx.forkedChainId];
  }, 20 * 1000);

  afterEach(() => {
    testClient.reset();
  }, 4 * 1000);

  // skip for now - we need to make this work on zora testnet chain too
  it<TestContext>(
    "can sign on the forked premint contract",
    async ({ fixedPriceMinterAddress, forkedChainId }) => {
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      const preminterAddress = zoraCreator1155PremintExecutorAddress[
        forkedChainId as keyof typeof zoraCreator1155PremintExecutorAddress
      ] as Address;

      const contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: 999,
          premintConfig,
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
  it<TestContext>(
    "can sign and recover a signature",
    async ({
      preminterAddress: preminterAddress,
      anvilChainId,
      fixedPriceMinterAddress,
    }) => {
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      const contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: anvilChainId,
          premintConfig,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const recoveredAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "recoverSigner",
        args: [premintConfig, contractAddress, signedMessage],
      });

      expect(recoveredAddress).to.equal(creatorAccount);
    },

    20 * 1000,
  );
  it<TestContext>(
    "can sign and mint multiple tokens",
    async ({
      zoraMintFee,
      anvilChainId,
      preminterAddress: preminterAddress,
      fixedPriceMinterAddress,
    }) => {
      // setup contract and token creation parameters
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig({
        contractAdmin: creatorAccount,
      });

      // lets make it a random number to not break the existing tests that expect fresh data
      premintConfig.uid = Math.round(Math.random() * 1000000);

      let contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // have creator sign the message to create the contract
      // and the token
      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: anvilChainId,
          premintConfig,
        }),
        account: creatorAccount,
      });

      const quantityToMint = 2n;

      const valueToSend =
        (zoraMintFee + premintConfig.tokenConfig.pricePerToken) *
        quantityToMint;

      const comment = "I love this!";

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("10"),
      });

      // get the premint status - it should not be minted
      let [contractCreated, tokenId] = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "premintStatus",
        args: [contractAddress, premintConfig.uid],
      });

      expect(contractCreated).toBe(false);
      expect(tokenId).toBe(0n);

      // now have the collector execute the first signed message;
      // it should create the contract, the token,
      // and min the quantity to mint tokens to the collector
      // the signature along with contract + token creation
      // parameters are required to call this function
      const mintHash = await walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        address: preminterAddress,
        args: [
          contractConfig,
          premintConfig,
          signedMessage,
          quantityToMint,
          comment,
        ],
        value: valueToSend,
      });

      // ensure it succeeded
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: mintHash,
      });

      expect(receipt.status).toBe("success");

      // fetch the premint token id
      [contractCreated, tokenId] = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "premintStatus",
        args: [contractAddress, premintConfig.uid],
      });

      expect(tokenId).not.toBe(0n);

      // now use what was created, to get the balance from the created contract
      const tokenBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, tokenId],
      });

      // get token balance - should be amount that was created
      expect(tokenBalance).toBe(quantityToMint);

      const premintConfig2 = {
        ...premintConfig,
        uid: premintConfig.uid + 1,
        tokenConfig: {
          ...premintConfig.tokenConfig,
          tokenURI: "ipfs://tokenIpfsId2",
          pricePerToken: parseEther("0.05"),
        },
      };

      // sign the message to create the second token
      const signedMessage2 = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: foundry.id,
          premintConfig: premintConfig2,
        }),
        account: creatorAccount,
      });

      const quantityToMint2 = 4n;

      const valueToSend2 =
        (zoraMintFee + premintConfig2.tokenConfig.pricePerToken) *
        quantityToMint2;

      // now have the collector execute the second signed message.
      // it should create a new token against the existing contract
      const mintHash2 = await walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        address: preminterAddress,
        args: [
          contractConfig,
          premintConfig2,
          signedMessage2,
          quantityToMint2,
          comment,
        ],
        value: valueToSend2,
      });

      expect(
        (await publicClient.waitForTransactionReceipt({ hash: mintHash2 }))
          .status,
      ).toBe("success");

      // now premint status for the second mint, it should be minted
      [, tokenId] = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "premintStatus",
        args: [contractAddress, premintConfig2.uid],
      });

      expect(tokenId).not.toBe(0n);

      // get balance of second token
      const tokenBalance2 = await publicClient.readContract({
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

  it<TestContext>("can decode the CreatorAttribution event", async ({
    zoraMintFee,
    anvilChainId,
    preminterAddress: preminterAddress,
    fixedPriceMinterAddress,
  }) => {
    const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
    const contractConfig = defaultContractConfig({
      contractAdmin: creatorAccount,
    });

    // lets make it a random number to not break the existing tests that expect fresh data
    premintConfig.uid = Math.round(Math.random() * 1000000);

    let contractAddress = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: "getContractAddress",
      args: [contractConfig],
    });

    // have creator sign the message to create the contract
    // and the token
    const signedMessage = await walletClient.signTypedData({
      ...preminterTypedDataDefinition({
        verifyingContract: contractAddress,
        // we need to sign here for the anvil chain, cause thats where it is run on
        chainId: anvilChainId,
        premintConfig,
      }),
      account: creatorAccount,
    });

    const quantityToMint = 2n;

    const valueToSend =
      (zoraMintFee + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

    const comment = "I love this!";

    await testClient.setBalance({
      address: collectorAccount,
      value: parseEther("10"),
    });

    // now have the collector execute the first signed message;
    // it should create the contract, the token,
    // and min the quantity to mint tokens to the collector
    // the signature along with contract + token creation
    // parameters are required to call this function
    const mintHash = await walletClient.writeContract({
      abi: preminterAbi,
      functionName: "premint",
      account: collectorAccount,
      address: preminterAddress,
      args: [
        contractConfig,
        premintConfig,
        signedMessage,
        quantityToMint,
        comment,
      ],
      value: valueToSend,
    });

    // ensure it succeeded
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: mintHash,
    });

    expect(receipt.status).toBe("success");

    // get the CreatorAttribution event from the erc1155 contract:
    const topics = await publicClient.getContractEvents({
      abi: zoraCreator1155ImplABI,
      address: contractAddress,
      eventName: "CreatorAttribution",
    });

    expect(topics.length).toBe(1);

    const creatorAttributionEvent = topics[0]!;

    const { creator, domainName, signature, structHash, version } =
      creatorAttributionEvent.args;

    const chainId = anvilChainId;

    // hash the eip712 domain based on the parameters emitted from the event:
    const hashedDomain = hashDomain({
      domain: {
        chainId,
        name: domainName,
        verifyingContract: contractAddress,
        version,
      },
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          {
            name: "chainId",
            type: "uint256",
          },
          {
            name: "verifyingContract",
            type: "address",
          },
        ],
      },
    });

    // re-build the eip-712 typed data hash, consisting of the hashed domain and the structHash emitted from the event:
    const parts: Hex[] = ["0x1901", hashedDomain, structHash!];

    const hashedTypedData = keccak256(concat(parts));

    const recoveredSigner = await recoverAddress({
      hash: hashedTypedData,
      signature: signature!,
    });

    expect(recoveredSigner).toBe(creator);
  });
});
