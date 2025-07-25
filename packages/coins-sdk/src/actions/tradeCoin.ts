import { permit2ABI, permit2Address } from "@zoralabs/protocol-deployments";
import {
  Account,
  Address,
  erc20Abi,
  WalletClient,
  maxUint256,
  Hex,
} from "viem";
import { base } from "viem/chains";
import { postQuote, PostQuoteResponse } from "../client";
import { GenericPublicClient } from "../utils/genericPublicClient";

type TradeERC20 = {
  type: "erc20";
  address: Address;
};

type TradeETH = {
  type: "eth";
};

type PermitDetails = {
  token: Address;
  amount: bigint;
  expiration: number;
  nonce: number;
};

type Permit = {
  details: PermitDetails;
  spender: Address;
  sigDeadline: bigint;
};

type PermitDetailsStringAmounts = {
  token: Address;
  amount: string;
  expiration: number;
  nonce: number;
};

type PermitStringAmounts = {
  details: PermitDetailsStringAmounts;
  spender: Address;
  sigDeadline: string;
};

type SignatureWithPermit<TPermit = Permit> = {
  signature: Hex;
  permit: TPermit;
};

function convertBigIntToString(permit: Permit): PermitStringAmounts {
  return {
    ...permit,
    details: {
      ...permit.details,
      amount: `${permit.details.amount}`,
    },
    sigDeadline: `${permit.sigDeadline}`,
  };
}

const PERMIT_SINGLE_TYPES = {
  PermitSingle: [
    { name: "details", type: "PermitDetails" },
    { name: "spender", type: "address" },
    { name: "sigDeadline", type: "uint256" },
  ],
  PermitDetails: [
    { name: "token", type: "address" },
    { name: "amount", type: "uint160" },
    { name: "expiration", type: "uint48" },
    { name: "nonce", type: "uint48" },
  ],
};

type TradeCurrency = TradeERC20 | TradeETH;

export type TradeParameters = {
  sell: TradeCurrency;
  buy: TradeCurrency;
  amountIn: bigint;
  slippage?: number;
  // can be smart wallet or EOA here.
  sender: Address;
  // needs to be EOA, if signer is blank assumes EOA in sender.
  signer?: Address;
  recipient?: Address;
  signatures?: SignatureWithPermit<PermitStringAmounts>[];
  permitActiveSeconds?: number;
};

export async function tradeCoin({
  tradeParameters,
  walletClient,
  account,
  publicClient,
  validateTransaction = true,
}: {
  tradeParameters: TradeParameters;
  walletClient: WalletClient;
  account?: Account | Address;
  publicClient: GenericPublicClient;
  validateTransaction?: boolean;
}) {
  const quote = await createTradeCall(tradeParameters);

  if (!account) {
    account = walletClient.account;
  }
  if (!account) {
    throw new Error("Account is required");
  }

  // Set default recipient to wallet sender address if not provided
  if (!tradeParameters.recipient) {
    tradeParameters.recipient =
      typeof account === "string" ? account : account.address;
  }

  // todo replace any
  const signatures: { signature: Hex; permit: any }[] = [];
  if (quote.permits) {
    for (const permit of quote.permits) {
      // return values: amount, expiration, nonce
      const [, , nonce] = await publicClient.readContract({
        abi: permit2ABI,
        address: permit2Address[base.id],
        functionName: "allowance",
        args: [
          permit.permit.details.token as Address,
          typeof account === "string" ? account : account.address,
          permit.permit.spender as Address,
        ],
      });
      const permitToken = permit.permit.details.token as Address;
      const allowance = await publicClient.readContract({
        abi: erc20Abi,
        address: permitToken,
        functionName: "allowance",
        args: [
          typeof account === "string" ? account : account.address,
          permit2Address[base.id],
        ],
      });
      if (allowance < BigInt(permit.permit.details.amount)) {
        const approvalTx = await walletClient.writeContract({
          abi: erc20Abi,
          address: permitToken,
          functionName: "approve",
          chain: base,
          args: [permit2Address[base.id], maxUint256],
          account,
        });
        await publicClient.waitForTransactionReceipt({
          hash: approvalTx,
        });
      }
      const message = {
        details: {
          token: permit.permit.details.token as Address,
          amount: BigInt(permit.permit.details.amount!),
          expiration: Number(permit.permit.details.expiration!),
          nonce: nonce,
        },
        spender: permit.permit.spender as Address,
        sigDeadline: BigInt(permit.permit.sigDeadline!),
      };
      const signature = await walletClient.signTypedData({
        domain: {
          name: "Permit2",
          chainId: base.id,
          verifyingContract: permit2Address[base.id],
        },
        primaryType: "PermitSingle",
        types: PERMIT_SINGLE_TYPES,
        message,
        account: typeof account === "string" ? account : account.address,
      });
      signatures.push({
        signature,
        permit: convertBigIntToString(message),
      });
    }
  }

  const newQuote = await createTradeCall({
    ...tradeParameters,
    signatures,
  });

  const call = {
    to: newQuote.call.target as Address,
    data: newQuote.call.data as Hex,
    value: BigInt(newQuote.call.value),
    chain: base,
    account,
  };

  // simulate call
  if (validateTransaction) {
    await publicClient.call(call);
  }

  const gasEstimate = validateTransaction
    ? await publicClient.estimateGas(call)
    : 10_000_000n;
  const gasPrice = await publicClient.getGasPrice();

  const tx = await walletClient.sendTransaction({
    ...call,
    gasPrice,
    gas: gasEstimate,
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: tx,
  });

  return receipt;
}

export async function createTradeCall(
  tradeParameters: TradeParameters,
): Promise<PostQuoteResponse> {
  if (tradeParameters.slippage && tradeParameters.slippage > 1) {
    throw new Error("Slippage must be less than 1, max 0.99");
  }
  if (tradeParameters.amountIn === BigInt(0)) {
    throw new Error("Amount in must be greater than 0");
  }

  const quote = await postQuote({
    body: {
      tokenIn: tradeParameters.sell,
      tokenOut: tradeParameters.buy,
      amountIn: tradeParameters.amountIn.toString(),
      slippage: tradeParameters.slippage,
      chainId: base.id,
      sender: tradeParameters.sender,
      recipient: tradeParameters.recipient || tradeParameters.sender,
      signatures: tradeParameters.signatures,
    },
  });

  if (!quote.data) {
    console.error(quote);
    throw new Error("Quote failed");
  }

  return quote.data;
}
