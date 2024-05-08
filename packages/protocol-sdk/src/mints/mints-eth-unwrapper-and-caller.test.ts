import { describe, expect } from "vitest";

import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  mintsEthUnwrapperAndCallerABI,
  mintsEthUnwrapperAndCallerAddress,
  mintsEthUnwrapperAndCallerConfig,
  zoraCreator1155ImplABI,
  zoraMints1155ABI,
  zoraMints1155Address,
  zoraMintsManagerImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  Hex,
  PublicClient,
  encodeFunctionData,
  parseEther,
} from "viem";
import { mintsBalanceOfAccountParams } from "./mints-contracts";
import { base, zora, zoraSepolia } from "viem/chains";
import {
  getRelayCall,
  makeAndSignSponsoredRelayCall,
  validateAndExecuteSponsoredRelayCall,
} from "./mints-relay-example";
import { collectMINTsWithEth } from "./mints-contracts.test";
import {
  fixedPriceMinterMinterArguments,
  getFixedPricedMinter,
  waitForSuccess,
} from "src/test-utils";
import { unwrapAndForwardEthPermitAndTypedDataDefinition } from "./mints-eth-unwrapper-and-caller";

const randomNonce = (): bigint => BigInt(Math.round(Math.random() * 1_000_000));

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  forkBlockNumber: 12990454,
  anvilChainId: zora.id,
});

const makeLegacy1155MintCall = async ({
  publicClient,
  chainId,
  mintRecipient,
  tokenId,
  quantityToMint,
}: {
  publicClient: PublicClient;
  chainId: keyof typeof zoraMints1155Address;
  mintRecipient: Address;
  tokenId: bigint;
  quantityToMint: bigint;
}) => {
  const fixedPriceMinter = await getFixedPricedMinter({
    publicClient,
    chainId,
  });
  const minterArguments = fixedPriceMinterMinterArguments({
    mintRecipient,
  });

  // this is the external contract function that will be called
  // by relay on the other chain
  const mintCall = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "mint",
    args: [fixedPriceMinter, tokenId, quantityToMint, [], minterArguments],
  });
  // amount of eth required to mint the quantity of tokens on the other chain.
  // this value will be bridged by relay and passed through to the target
  // contract on the destination chain.
  const mintFee = parseEther("0.000777") * quantityToMint;

  return {
    mintCall,
    mintFee,
  };
};

describe("MintsEthUnwrapperAndCaller", () => {
  makeAnvilTest({
    forkUrl: forkUrls.zoraSepolia,
    forkBlockNumber: 7297306,
    anvilChainId: zoraSepolia.id,
  })(
    "can be used to gaslessly unwrap MINTs values and collect older versions of 1155 contracts",
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

      const quantityToMintOn1155 = 3n;

      const tokenId = 1n;

      // this is the external contract that will be called
      const legacy1155Address = "0x2988C3b4F3A823488e4E2d70F23bD66366639b81";

      const { mintCall: contractCall, mintFee } = await makeLegacy1155MintCall({
        chainId,
        mintRecipient: collectorAccount!,
        tokenId,
        quantityToMint: quantityToMintOn1155,
        publicClient,
      });

      // get typed data to sign, as well as permit to collect with
      const { typedData: batchTransferTypeData, permit: batchTransferPermit } =
        unwrapAndForwardEthPermitAndTypedDataDefinition({
          from: collectorAccount!,
          chainId: chainId,
          nonce: randomNonce(),
          deadline: (await publicClient.getBlock()).timestamp + 10n,
          // token ids to unwrap and burn - must be eth based token ids
          tokenIds: [mintsTokenId],
          // quantities to unwrap and burn
          quantities: [quantityToMintOn1155],
          callWithEth: {
            // external address to call
            address: legacy1155Address,
            // external contract call
            call: contractCall,
            // value to send to external contract, extra value from mints
            // will be refunded
            value: mintFee,
          },
        });

      const permitBatchSignature = await walletClient.signTypedData(
        batchTransferTypeData,
      );

      // now simulate and execute the transaction
      const permitBatchSimulated = await publicClient.simulateContract({
        abi: zoraMints1155ABI,
        address: zoraMints1155Address[chainId],
        functionName: "permitSafeTransferBatch",
        args: [batchTransferPermit, permitBatchSignature],
        account: permitExecutorAccount,
      });

      await waitForSuccess(
        await walletClient.writeContract(permitBatchSimulated.request),
        publicClient,
      );

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: collectorAccount!,
            chainId: chainId,
          }),
        ),
      ).toBe(initialMintsBalance - quantityToMintOn1155);

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

      expect(tokenBalance).toBe(quantityToMintOn1155);
    },
    20_000,
  );

  anvilTest(
    "can be used gaslessly to unwrap MINTs values and collect on other chains using Relay",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      // this test shows how an account can unwrap eth value of MINTs
      // and use relay to mint a zora creator 1155 token on another chain.

      // it does this by:
      // 1. getting the relay call to make on the other chain
      // 2. signing a permit to transfer the MINTs to the eth unwrapper and caller,
      // and using that unwrapped value to call relay with the unwrapped value.
      // 3. Executing a transaction on the mintsEthUnwrapperAndCaller by passing
      // in the permit, signature, and relay fee as the payable value,
      // which unwraps the transferred MINTs eth, adds the relay fee, and calls
      // relay with that value.
      const [collectorAccount, permitExecutorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectMINTsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: initialMintsQuantityToMint,
      });

      const tokenId = 6n;

      const quantityToMint = 3n;

      const destinationChainId = base.id;

      // address of the 1155 contract on the other chain that will be called
      const destinationContractAddress =
        "0x5f69da5da41e5472afb88fc291e7a92b7f15fbc5" as Address;

      const { mintCall, mintFee: mintFeeOnOtherChain } =
        await makeLegacy1155MintCall({
          publicClient,
          chainId,
          mintRecipient: collectorAccount!,
          tokenId,
          quantityToMint,
        });

      // build the cross chain relay call by requesting it from their api.
      // this will give: address to call, data to send in call, and value to send
      // returns the call to relay, and how much of the value being sent to them is the fee
      const { relayCall: relayCall, relayFee: relayFee } = await getRelayCall({
        // the mints eth unwrapper and caller contract is the account
        // that is doing to be depositing the eth value into relay
        depositingAccount: mintsEthUnwrapperAndCallerAddress[chainId],
        // the chain to call from (current chain)
        originChainId: chain.id,
        // the chain that the call will be executed on
        toChainId: destinationChainId,
        // the tx to call on the other chain:
        tx: {
          to: destinationContractAddress,
          value: mintFeeOnOtherChain,
          data: mintCall,
        },
      });

      // build permit to transfer mints to the mintsEthUnwrapperAndCaller,
      // and call the relay with the unwrapped value.
      // get data to be signed
      const { typedData: transferTypeData, permit: transferPermit } =
        unwrapAndForwardEthPermitAndTypedDataDefinition({
          // mints will be transferred from this account
          from: collectorAccount!,
          chainId: chainId,
          // random nonce
          nonce: randomNonce(),
          // deadling for signature
          deadline: (await publicClient.getBlock()).timestamp + 100n,
          // token ids to unwrap and burn - must be eth based token ids
          tokenIds: [mintsTokenId],
          // quantities to unwrap and burn
          quantities: [quantityToMint],
          callWithEth: {
            // external address to call
            address: relayCall.to,
            // external contract call
            call: relayCall.data as Hex,
            // value to send to external contract, extra value from mints
            // will be refunded
            value: BigInt(relayCall.value),
          },
        });

      // sign the permit
      const permitSignature =
        await walletClient.signTypedData(transferTypeData);

      const collectorBalanceBefore = await publicClient.getBalance({
        address: collectorAccount!,
      });

      const collectorMintsBalanceBefore = await publicClient.readContract(
        mintsBalanceOfAccountParams({
          account: collectorAccount!,
          chainId: chainId,
        }),
      );

      // now we call a payable function on the mints eth unwrapper and caller contract,
      // with the permit and corresponding signature to transfer the mints to the unwrapper,
      // and call relay with the unwrapped value + relay fee.
      // the payable value on this call is the relay fee, which is added to the unwrapped
      // value of the mints and sent to the other chain.
      // any remaining value from the unwrapped MINTs is refunded to the original caller.
      const simulated = await publicClient.simulateContract({
        abi: mintsEthUnwrapperAndCallerABI,
        address: mintsEthUnwrapperAndCallerAddress[chainId],
        functionName: "permitWithAdditionalValue",
        args: [transferPermit, permitSignature],
        account: permitExecutorAccount!,
        // we must call this functio
        value: relayFee,
      });

      // wait for the transaction to succeed.
      await waitForSuccess(
        await walletClient.writeContract(simulated.request),
        publicClient,
      );

      const ethUnwrapperBalance = await publicClient.getBalance({
        address: mintsEthUnwrapperAndCallerAddress[chainId],
      });

      // check that no remaining eth is left in the unwrapper
      expect(ethUnwrapperBalance).toBe(0n);

      // collector balance should not have changed
      expect(
        await publicClient.getBalance({
          address: collectorAccount!,
        }),
      ).toBe(collectorBalanceBefore);

      expect(
        await publicClient.readContract(
          mintsBalanceOfAccountParams({
            account: collectorAccount!,
            chainId: chainId,
          }),
        ),
      ).toBe(collectorMintsBalanceBefore - quantityToMint);
    },
    10_000,
  );
  anvilTest(
    "can be used gaslessly to unwrap MINTs values and collect on other chains using Relay with a signature by the executor",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      // this is similar to the above test, but it shows how the executor
      // can sign a message indicating its willing to do the said relay call and pay the extra relay fee,
      // with a deadline.
      // this is a flow starts with a relay call being done on a server, and an executing account
      // signing a message indicating its willing to execute that call and pay the relay fee.
      // It the returns this call to the client, and the client signs the permit to transfer the mints
      // with that call.
      // That signature, premit, and original signature with deadline are then passed to the server,
      // the server validates the original signature, checks the deadlined hasn't passed, and then executes the relay call,
      // paying the relay fee.
      const [collectorAccount, permitExecutorAccount] =
        await walletClient.getAddresses();

      const chainId = chain.id as keyof typeof zoraMintsManagerImplAddress;

      const initialMintsQuantityToMint = 20n;

      const mintsTokenId = await collectMINTsWithEth({
        publicClient,
        walletClient,
        chainId,
        collectorAccount: collectorAccount!,
        quantityToMint: initialMintsQuantityToMint,
      });

      const tokenId = 6n;

      const quantityToMint = 3n;

      const destinationChainId = base.id;

      // address of the 1155 contract on the other chain that will be called
      const destinationContractAddress =
        "0x5f69da5da41e5472afb88fc291e7a92b7f15fbc5" as Address;

      const { mintCall, mintFee: mintFeeOnOtherChain } =
        await makeLegacy1155MintCall({
          publicClient,
          chainId,
          mintRecipient: collectorAccount!,
          tokenId,
          quantityToMint,
        });

      // this call would happen on the server, which would call relay, and generate
      // data to sign for the permit. It would also sign a message indicating it would be willing
      // to pay the relay fee.  This signature is used later.
      const {
        safeTransferData,
        signature: sponsoredRelayCallSignature,
        deadline,
        additionalValueToSend,
      } = await makeAndSignSponsoredRelayCall({
        // this is the account that is to later execute the transaction and pay the additional relay fee.
        // it will be the account that signs the message.
        executingAccount: permitExecutorAccount!,
        // the chain to call from (current chain)
        originChainId: chainId,
        // the chain that the call will be executed on
        toChainId: destinationChainId,
        // the tx to call on the other chain
        tx: {
          to: destinationContractAddress,
          value: mintFeeOnOtherChain,
          data: mintCall,
        },
        walletClient,
      });

      // build permit to transfer mints to the mintsEthUnwrapperAndCaller,
      // and call the relay with the unwrapped value, and gets the data
      // to be signed. This would be built on the client-side
      const { typedData: transferTypeData, permit: transferPermit } =
        unwrapAndForwardEthPermitAndTypedDataDefinition({
          // mints will be transferred from this account
          from: collectorAccount!,
          chainId: chainId,
          // random nonce
          nonce: randomNonce(),
          // deadling for signature
          deadline: (await publicClient.getBlock()).timestamp + 100n,
          // token ids to unwrap and burn - must be eth based token ids
          tokenIds: [mintsTokenId],
          // quantities to unwrap and burn
          quantities: [quantityToMint],
          // we already have the data to call the external contract
          safeTransferData,
        });

      // have the collector sign the permit
      const permitSignature =
        await walletClient.signTypedData(transferTypeData);

      // this call would happen on the server after the collector signs a message.
      // the server would be passed the permit, permit signature, and
      // sponsored call signature created above, then validate the sponsored call signature.
      await validateAndExecuteSponsoredRelayCall({
        permit: transferPermit,
        permitSignature,
        sponsoredCallSignature: sponsoredRelayCallSignature,
        additionalValueToSend,
        deadline,
        chainId,
        executingAccount: permitExecutorAccount!,
        walletClient,
        publicClient,
      });
    },
    10_000,
  );
});
