import { describe, it, expect } from "vitest";
import { type Address, type Hex, encodeAbiParameters } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  NoSmartWalletFoundError,
  NotSmartWalletOwnerError,
  SmartWalletNotDeployedError,
  resolveConnection,
} from "./connect.js";

const KEY = ("0x" + "1".repeat(64)) as Hex;
const OWNER = privateKeyToAccount(KEY).address;
const PREDICTED = "0x1111111111111111111111111111111111111111" as Address;
const OVERRIDE = "0x2222222222222222222222222222222222222222" as Address;
const OTHER = "0x3333333333333333333333333333333333333333" as Address;

/**
 * A minimal fake of the on-chain client used by the discovery code: it answers
 * the ZoraAccountManager prediction, the deploy check, and the smart-wallet owner
 * reads, all from in-memory fixtures.
 */
function makeClient(opts: {
  predicted?: Address;
  deployed?: Address[];
  owners?: Record<string, Address[]>;
}) {
  const deployed = new Set((opts.deployed ?? []).map((a) => a.toLowerCase()));
  const owners = opts.owners ?? {};
  return {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async readContract(args: any) {
      if (args.functionName === "getAddress") {
        return opts.predicted ?? PREDICTED;
      }
      const list = owners[(args.address as string).toLowerCase()] ?? [];
      if (args.functionName === "nextOwnerIndex") {
        return BigInt(list.length);
      }
      if (args.functionName === "ownerAtIndex") {
        const owner = list[Number(args.args[0])];
        return encodeAbiParameters([{ type: "address" }], [owner]);
      }
      throw new Error(`unexpected functionName ${args.functionName}`);
    },
    async getCode({ address }: { address: Address }) {
      return deployed.has(address.toLowerCase()) ? ("0x60006000" as Hex) : "0x";
    },
  };
}

describe("resolveConnection", () => {
  describe("auto-discovery", () => {
    it("returns the deterministic smart wallet when deployed", async () => {
      const client = makeClient({
        predicted: PREDICTED,
        deployed: [PREDICTED],
      });

      const result = await resolveConnection({ privateKey: KEY, client });

      expect(result).toEqual({
        ownerAddress: OWNER,
        smartWalletAddress: PREDICTED,
        discovered: true,
      });
    });

    it("throws NoSmartWalletFoundError when the predicted wallet isn't deployed", async () => {
      const client = makeClient({ predicted: PREDICTED, deployed: [] });

      await expect(
        resolveConnection({ privateKey: KEY, client }),
      ).rejects.toBeInstanceOf(NoSmartWalletFoundError);
      await expect(
        resolveConnection({ privateKey: KEY, client }),
      ).rejects.toMatchObject({ ownerAddress: OWNER });
    });
  });

  describe("explicit override", () => {
    it("accepts a deployed wallet the key owns", async () => {
      const client = makeClient({
        deployed: [OVERRIDE],
        owners: { [OVERRIDE.toLowerCase()]: [OWNER] },
      });

      const result = await resolveConnection({
        privateKey: KEY,
        client,
        smartWalletOverride: OVERRIDE,
      });

      expect(result).toEqual({
        ownerAddress: OWNER,
        smartWalletAddress: OVERRIDE,
        discovered: false,
      });
    });

    it("accepts a wallet where the key is one of several owners", async () => {
      const client = makeClient({
        deployed: [OVERRIDE],
        owners: { [OVERRIDE.toLowerCase()]: [OTHER, OWNER] },
      });

      const result = await resolveConnection({
        privateKey: KEY,
        client,
        smartWalletOverride: OVERRIDE,
      });

      expect(result.smartWalletAddress).toBe(OVERRIDE);
      expect(result.discovered).toBe(false);
    });

    it("throws SmartWalletNotDeployedError when the override has no code", async () => {
      const client = makeClient({ deployed: [] });

      await expect(
        resolveConnection({
          privateKey: KEY,
          client,
          smartWalletOverride: OVERRIDE,
        }),
      ).rejects.toBeInstanceOf(SmartWalletNotDeployedError);
    });

    it("throws NotSmartWalletOwnerError when the key isn't an owner", async () => {
      const client = makeClient({
        deployed: [OVERRIDE],
        owners: { [OVERRIDE.toLowerCase()]: [OTHER] },
      });

      await expect(
        resolveConnection({
          privateKey: KEY,
          client,
          smartWalletOverride: OVERRIDE,
        }),
      ).rejects.toBeInstanceOf(NotSmartWalletOwnerError);
    });
  });
});
