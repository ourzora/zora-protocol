import { describe, expect, it } from "vitest";
import {
  decodeAbiParameters,
  hashMessage,
  recoverAddress,
  toHex,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  createEoaAuth,
  createSmartWalletAuth,
  type PrivyAuthProvider,
} from "./identity.js";
import { toReplaySafeHash } from "./signer.js";

const PRIVATE_KEY =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const OWNER = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as const;
const SCW = "0x1111111111166b7FE7bd91427724B487980aFc69" as const;

describe("createEoaAuth", () => {
  it("produces an EOA signer for the key's own address with EIP-191 signing", async () => {
    const { signerSpec } = createEoaAuth(PRIVATE_KEY);
    expect(signerSpec.type).toBe("EOA");
    expect(signerSpec.address).toBe(OWNER);

    const bytes = await signerSpec.signMessage("gm");
    const sig = toHex(bytes);
    // EIP-191 personal-sign recovers to the signing EOA.
    const recovered = await recoverAddress({ hash: hashMessage("gm"), signature: sig });
    expect(recovered).toBe(OWNER);
  });

  it("has no API token in dev mode", async () => {
    const auth = createEoaAuth(PRIVATE_KEY);
    expect(await auth.getApiToken()).toBeUndefined();
  });
});

describe("createSmartWalletAuth", () => {
  // A fake auth layer: the owner EOA raw-signs the 32-byte hash (no prefix),
  // exactly what the real Privy layer must do.
  const ownerAccount = privateKeyToAccount(PRIVATE_KEY);
  const provider: PrivyAuthProvider = {
    getSmartWalletAddress: () => SCW,
    getOwnerAddress: () => OWNER,
    getOwners: () => [{ ownerAddress: OWNER, ownerIndex: 3 }],
    signHash: (hash: Hex) => ownerAccount.sign({ hash }),
    getAccessToken: async () => "privy.jwt.token",
  };

  it("builds an SCW signer over the smart-wallet address", () => {
    const { signerSpec } = createSmartWalletAuth(provider);
    expect(signerSpec.type).toBe("SCW");
    expect(signerSpec.address).toBe(SCW);
    expect(signerSpec.chainId).toBe(8453);
  });

  it("wraps a raw-hash signature with the resolved owner index", async () => {
    const { signerSpec } = createSmartWalletAuth(provider);
    const bytes = await signerSpec.signMessage("hello xmtp");

    const [decoded] = decodeAbiParameters(
      [
        {
          components: [
            { name: "ownerIndex", type: "uint8" },
            { name: "signatureData", type: "bytes" },
          ],
          type: "tuple",
        },
      ],
      toHex(bytes),
    ) as [{ ownerIndex: number; signatureData: Hex }];

    // Owner index came from the provider's owner set.
    expect(decoded.ownerIndex).toBe(3);

    // The inner signature is over the replay-safe hash and recovers to the owner —
    // proving the SCW signer signs the RAW hash, not an EIP-191-prefixed message.
    const replaySafeHash = toReplaySafeHash({
      chainId: 8453,
      address: SCW,
      hash: hashMessage("hello xmtp"),
    });
    const recovered = await recoverAddress({
      hash: replaySafeHash,
      signature: decoded.signatureData,
    });
    expect(recovered).toBe(OWNER);
  });

  it("exposes the Privy access token", async () => {
    const auth = createSmartWalletAuth(provider);
    expect(await auth.getApiToken()).toBe("privy.jwt.token");
  });
});
