import {
  type Address,
  type Hash,
  type Hex,
  encodeAbiParameters,
  encodePacked,
  hashTypedData,
  isAddressEqual,
  parseSignature,
  size,
} from "viem";

/**
 * Coinbase Smart Wallet (CSW) signature helpers, ported verbatim from the Zora
 * web app (`frontend/apps/web/utils/contract/signTypedDataWithSmartWallet.ts`
 * and `@ourzora/utils`). They are pure `viem` with no browser dependencies, so
 * they run unchanged under Node.
 *
 * XMTP authenticates a smart-wallet inbox by verifying an ERC-1271 signature
 * over a replay-safe hash. The owning EOA signs the *raw* 32-byte replay-safe
 * hash (not an EIP-191 personal_sign); the resulting 65-byte signature is then
 * wrapped with the owner index so the CSW contract can validate it. Getting this
 * wrong (prefixed signing, bad wrapping) yields an invalid XMTP identity, which
 * is why this module is isolated and exhaustively unit-tested.
 */

/** Packs a 65-byte ECDSA signature into the (r, s, v) form the CSW expects. */
const getSignatureData = (signature: Hex): Hex => {
  if (size(signature) !== 65) return signature;
  const parsed = parseSignature(signature);
  return encodePacked(
    ["bytes32", "bytes32", "uint8"],
    [parsed.r, parsed.s, parsed.yParity === 0 ? 27 : 28],
  );
};

/**
 * Wraps an owner signature in the `(ownerIndex, signatureData)` tuple the
 * Coinbase Smart Wallet validates against its owner set.
 */
export const wrapSignature = ({
  ownerIndex = 0,
  signature,
}: {
  ownerIndex?: number;
  signature: Hex;
}): Hex =>
  encodeAbiParameters(
    [
      {
        components: [
          { name: "ownerIndex", type: "uint8" },
          { name: "signatureData", type: "bytes" },
        ],
        type: "tuple",
      },
    ],
    [{ ownerIndex, signatureData: getSignatureData(signature) }],
  );

/**
 * Wraps a digest in the CSW replay-safe typed-data hash for a given chain and
 * wallet address. The owning EOA signs the returned hash.
 */
export const toReplaySafeHash = ({
  chainId,
  address,
  hash,
}: {
  chainId: number;
  address: Address;
  hash: Hash;
}): Hex =>
  hashTypedData({
    domain: {
      chainId,
      name: "Coinbase Smart Wallet",
      verifyingContract: address,
      version: "1",
    },
    types: {
      CoinbaseSmartWalletMessage: [{ name: "hash", type: "bytes32" }],
    },
    primaryType: "CoinbaseSmartWalletMessage",
    message: { hash },
  });

/** A Coinbase Smart Wallet owner entry, as returned by UAPI `GraphQLSmartWalletProfile.owners`. */
export interface SmartWalletOwner {
  ownerAddress: Address;
  ownerIndex: number;
}

/**
 * Resolves the CSW owner index for the signing EOA from the smart wallet's owner
 * set. Mirrors `getOwnerIndexForWallet` from `@ourzora/utils`. Falls back to 0
 * when the owner set is unknown or the address is not found.
 */
export const getOwnerIndexForWallet = ({
  owners,
  ownerAddress,
}: {
  owners?: readonly SmartWalletOwner[] | null;
  ownerAddress: Address;
}): number => {
  if (!owners) return 0;
  return (
    owners.find((owner) => isAddressEqual(owner.ownerAddress, ownerAddress))
      ?.ownerIndex ?? 0
  );
};
