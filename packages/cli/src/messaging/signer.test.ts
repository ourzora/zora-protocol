import { describe, expect, it } from "vitest";
import {
  decodeAbiParameters,
  hashMessage,
  parseSignature,
  size,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  getOwnerIndexForWallet,
  toReplaySafeHash,
  wrapSignature,
} from "./signer.js";

// Anvil account #1 — deterministic key, safe to commit in tests.
const PRIVATE_KEY =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const OWNER = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as const;
const SCW = "0x1111111111166b7FE7bd91427724B487980aFc69" as const;

describe("toReplaySafeHash", () => {
  it("matches the known Coinbase Smart Wallet replay-safe digest", () => {
    // Regression fixture generated with viem against the ported helper. If this
    // changes, the CSW domain/typed-data shape drifted and signatures will break.
    const hash = toReplaySafeHash({
      chainId: 8453,
      address: SCW,
      hash: hashMessage("hello xmtp"),
    });
    expect(hash).toBe(
      "0xaa5dfa000620165e3aa2c6c3f38efb41935b4516fa76570e299be670dce90b10",
    );
  });

  it("is chain- and address-scoped (replay safety)", () => {
    const base = { hash: hashMessage("m") };
    const onBase = toReplaySafeHash({ ...base, chainId: 8453, address: SCW });
    const onMainnet = toReplaySafeHash({ ...base, chainId: 1, address: SCW });
    const otherWallet = toReplaySafeHash({
      ...base,
      chainId: 8453,
      address: "0x2222222222222222222222222222222222222222",
    });
    expect(onBase).not.toBe(onMainnet);
    expect(onBase).not.toBe(otherWallet);
  });
});

describe("wrapSignature", () => {
  it("packs a 65-byte signature into the (ownerIndex, r||s||v) tuple", () => {
    const account = privateKeyToAccount(PRIVATE_KEY);
    const replaySafeHash = toReplaySafeHash({
      chainId: 8453,
      address: SCW,
      hash: hashMessage("hello xmtp"),
    });
    return account.sign({ hash: replaySafeHash }).then((rawSig) => {
      const wrapped = wrapSignature({ ownerIndex: 2, signature: rawSig });

      // Decodes back to (ownerIndex=2, packed signatureData of length 65).
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
        wrapped,
      ) as [{ ownerIndex: number; signatureData: Hex }];

      expect(decoded.ownerIndex).toBe(2);
      expect(size(decoded.signatureData)).toBe(65);

      // signatureData is r(32) || s(32) || v(1), with v normalized to 27/28.
      const parsed = parseSignature(rawSig);
      const v = parseInt(decoded.signatureData.slice(-2), 16);
      expect(v === 27 || v === 28).toBe(true);
      expect(decoded.signatureData.startsWith(parsed.r)).toBe(true);
    });
  });

  it("defaults ownerIndex to 0", async () => {
    const account = privateKeyToAccount(PRIVATE_KEY);
    const sig = await account.sign({ hash: hashMessage("anything") });
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
      wrapSignature({ signature: sig }),
    ) as [{ ownerIndex: number }];
    expect(decoded.ownerIndex).toBe(0);
  });
});

describe("getOwnerIndexForWallet", () => {
  it("finds the owner index by address (case-insensitive)", () => {
    expect(
      getOwnerIndexForWallet({
        owners: [
          { ownerAddress: "0xAbc0000000000000000000000000000000000001", ownerIndex: 0 },
          { ownerAddress: OWNER, ownerIndex: 2 },
        ],
        ownerAddress: OWNER.toLowerCase() as `0x${string}`,
      }),
    ).toBe(2);
  });

  it("falls back to 0 when owners are unknown or the address is absent", () => {
    expect(getOwnerIndexForWallet({ owners: null, ownerAddress: OWNER })).toBe(0);
    expect(
      getOwnerIndexForWallet({
        owners: [{ ownerAddress: SCW, ownerIndex: 5 }],
        ownerAddress: OWNER,
      }),
    ).toBe(0);
  });
});
