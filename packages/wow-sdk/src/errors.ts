import { Address } from "viem";

export class SlippageExceededError extends Error {
  constructor(
    public originalQuote: bigint,
    public updatedQuote: bigint,
  ) {
    super("Slippage exceeded");
    this.name = "SlippageExceededError";
    this.originalQuote = originalQuote;
    this.updatedQuote = updatedQuote;
  }
}

export class NoPoolAddressFoundError extends Error {
  constructor(public tokenAddress: Address) {
    super("No pool address found");
    this.name = "NoPoolAddressFoundError";
    this.tokenAddress = tokenAddress;
  }
}
