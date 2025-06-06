import { describe, expect, it } from "vitest";
import { createCoinCall } from "../src";
import { baseSepolia } from "viem/chains";
import { DeployCurrency } from "src/actions/createCoin";

describe("Create Coin Call", () => {
  it("create coin call valid uri", async () => {
    const createCoinRequest = await createCoinCall({
      name: "Test Coin",
      symbol: "TEST",
      uri: "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje",
      owners: ["0x9444390c01Dd5b7249E53FAc31290F7dFF53450D"],
      payoutRecipient: "0x9444390c01Dd5b7249E53FAc31290F7dFF53450D",
      initialPurchaseWei: 0n,
      chainId: baseSepolia.id,
      currency: DeployCurrency.ETH,
    });
    console.log(createCoinRequest);
  });
  it("create coin call valid uri", async () => {
    const createCoinRequest = await createCoinCall({
      name: "Test Coin",
      symbol: "TEST",
      uri: "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje",
      owners: ["0x9444390c01Dd5b7249E53FAc31290F7dFF53450D"],
      payoutRecipient: "0x9444390c01Dd5b7249E53FAc31290F7dFF53450D",
      chainId: baseSepolia.id,
      currency: DeployCurrency.ETH,
    });
    console.log(createCoinRequest);
  });

  it("create coin call invalid uri", async () => {
    await expect(
      createCoinCall({
        name: "Test Coin",
        symbol: "TEST",
        // resolves to an image
        uri: "ipfs://bafybeibx5wpwwztdhoijwot2ja634kmtlnlzl5mjdk3gtibpf4cttwvhzq",
        owners: ["0x9444390c01Dd5b7249E53FAc31290F7dFF53450D"],
        payoutRecipient: "0x9444390c01Dd5b7249E53FAc31290F7dFF53450D",
        chainId: baseSepolia.id,
      }),
    ).rejects.toThrow(
      "Metadata is not a valid JSON or plain text response type",
    );
  });
});
