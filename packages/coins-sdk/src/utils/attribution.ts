import { Hex, keccak256, slice, toHex } from "viem";

export function getAttribution(): Hex {
  const hash = keccak256(toHex("api-sdk.zora.engineering"));
  return slice(hash, 0, 4) as Hex;
}
