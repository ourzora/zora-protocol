import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address, type PrivateKeyAccount } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
vi.mock("@inquirer/input");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
}));
vi.mock("../lib/wallet.js");
vi.mock("../lib/analytics.js");
vi.mock("../lib/gas.js", () => ({
  gasErrorSuggestion: vi.fn(() => undefined),
}));
vi.mock("../lib/coin-ref.js", () => ({ resolveAmbiguousName: vi.fn() }));
vi.mock("../lib/edit.js", () => ({
  fetchCoinMetadata: vi.fn(),
  mergeMetadata: vi.fn(),
}));
vi.mock("node:fs", () => ({
  existsSync: vi.fn(),
  readFileSync: vi.fn(),
}));
vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  getCoin: vi.fn(),
  createZoraUploaderForCreator: vi.fn(),
  updateCoinURI: vi.fn(),
  updateCoinURISmartWallet: vi.fn(),
}));

import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import { existsSync, readFileSync } from "node:fs";
import {
  createZoraUploaderForCreator,
  getCoin,
  updateCoinURI,
  updateCoinURISmartWallet,
} from "@zoralabs/coins-sdk";
import { track } from "../lib/analytics.js";
import { resolveAmbiguousName } from "../lib/coin-ref.js";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { fetchCoinMetadata, mergeMetadata } from "../lib/edit.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import type { SmartWalletAccount } from "../lib/account/index.js";
import { coinEditCommand } from "./edit.js";

const EOA = `0x${"1".repeat(40)}` as Address;
const SMART_WALLET = `0x${"2".repeat(40)}` as Address;
const COIN = "0x1fa82d2ccbf747e2be25339fde108bddbf9381b6" as Address;
const TX_HASH = `0x${"a".repeat(64)}` as const;
const PK = `0x${"a".repeat(64)}`;

const PREV_METADATA = {
  name: "My Post",
  symbol: "POST",
  description: "old caption",
  image: "ipfs://bafyimageOld",
};

function runEdit(args: string[]) {
  return createProgram(coinEditCommand).parseAsync(["edit", ...args], {
    from: "user",
  });
}

describe("coin edit command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let savedEnvKey: string | undefined;

  const publicClient = {};
  const walletClient = {};
  const bundlerClient = { account: { address: SMART_WALLET } };
  const uploaderUpload = vi.fn();

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    savedEnvKey = process.env.ZORA_PRIVATE_KEY;
    delete process.env.ZORA_PRIVATE_KEY;

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getPrivateKey).mockReturnValue(PK);
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(input).mockResolvedValue("prompted caption");

    vi.mocked(existsSync).mockReturnValue(true);
    vi.mocked(readFileSync).mockReturnValue(Buffer.from("fake-image-bytes"));

    // Default identity: a configured smart wallet that is also the coin's creator.
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA } as PrivateKeyAccount,
      smartWalletAccount: { address: SMART_WALLET } as SmartWalletAccount,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
      bundlerClient,
    } as unknown as ReturnType<typeof createClients>);

    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          address: COIN,
          name: "My Post",
          symbol: "POST",
          description: "old caption",
          tokenUri: "ipfs://bafymeta",
          creatorAddress: SMART_WALLET,
        },
      },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);

    vi.mocked(fetchCoinMetadata).mockResolvedValue({ ...PREV_METADATA });
    vi.mocked(mergeMetadata).mockImplementation(
      (prev, edits) =>
        ({
          ...prev,
          ...(edits.imageUri !== undefined ? { image: edits.imageUri } : {}),
          ...(edits.description !== undefined
            ? { description: edits.description }
            : {}),
        }) as ReturnType<typeof mergeMetadata>,
    );

    // The image upload and the metadata upload reuse one uploader; distinguish
    // them by file name so a test can assert each happened.
    uploaderUpload.mockImplementation(async (file: File) => ({
      url: file.name === "metadata.json" ? "ipfs://newmeta" : "ipfs://imageNew",
    }));
    vi.mocked(createZoraUploaderForCreator).mockReturnValue({
      upload: uploaderUpload,
    } as unknown as ReturnType<typeof createZoraUploaderForCreator>);

    vi.mocked(updateCoinURISmartWallet).mockResolvedValue({
      hash: TX_HASH,
    } as Awaited<ReturnType<typeof updateCoinURISmartWallet>>);
    vi.mocked(updateCoinURI).mockResolvedValue({
      hash: TX_HASH,
    } as Awaited<ReturnType<typeof updateCoinURI>>);
  });

  afterEach(() => {
    if (savedEnvKey !== undefined) process.env.ZORA_PRIVATE_KEY = savedEnvKey;
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("edits the image and description via the smart wallet and outputs JSON", async () => {
    await runEdit([
      COIN,
      "--image",
      "./new.png",
      "--description",
      "new caption",
      "--json",
    ]);

    expect(mergeMetadata).toHaveBeenCalledWith(PREV_METADATA, {
      imageUri: "ipfs://imageNew",
      description: "new caption",
    });
    // Both the new image and the merged metadata are uploaded.
    expect(uploaderUpload).toHaveBeenCalledTimes(2);
    expect(updateCoinURISmartWallet).toHaveBeenCalledWith(
      { coin: COIN, newURI: "ipfs://newmeta" },
      bundlerClient,
      publicClient,
    );
    expect(updateCoinURI).not.toHaveBeenCalled();
    expect(parsedOutput()).toEqual({
      action: "edit",
      coin: COIN,
      name: "My Post",
      symbol: "POST",
      edited: ["image", "description"],
      tokenUri: "ipfs://newmeta",
      tx: TX_HASH,
      walletType: "smart_wallet",
    });
  });

  it("edits only the description without uploading a new image", async () => {
    await runEdit([COIN, "--description", "just the caption", "--json"]);

    expect(mergeMetadata).toHaveBeenCalledWith(PREV_METADATA, {
      imageUri: undefined,
      description: "just the caption",
    });
    expect(uploaderUpload).toHaveBeenCalledTimes(1); // metadata only
    expect(parsedOutput().edited).toEqual(["description"]);
  });

  it("edits only the image, leaving the description untouched", async () => {
    await runEdit([COIN, "--image", "./new.png", "--json"]);

    expect(mergeMetadata).toHaveBeenCalledWith(PREV_METADATA, {
      imageUri: "ipfs://imageNew",
      description: undefined,
    });
    expect(uploaderUpload).toHaveBeenCalledTimes(2);
    expect(parsedOutput().edited).toEqual(["image"]);
  });

  it("uses the EOA path when no smart wallet is configured", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA } as PrivateKeyAccount,
      smartWalletAccount: undefined,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          address: COIN,
          name: "My Post",
          symbol: "POST",
          description: "old caption",
          tokenUri: "ipfs://bafymeta",
          creatorAddress: EOA,
        },
      },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);

    await runEdit([COIN, "--description", "hi", "--json"]);

    expect(updateCoinURI).toHaveBeenCalledWith(
      { coin: COIN, newURI: "ipfs://newmeta" },
      walletClient,
      publicClient,
      { address: EOA },
    );
    expect(updateCoinURISmartWallet).not.toHaveBeenCalled();
    expect(parsedOutput().walletType).toBe("eoa");
  });

  it("resolves a name to an address before editing", async () => {
    vi.mocked(resolveAmbiguousName).mockResolvedValue({
      kind: "found",
      coin: { name: "My Post", address: COIN },
    } as Awaited<ReturnType<typeof resolveAmbiguousName>>);

    await runEdit(["my-post", "--description", "hi", "--json"]);

    expect(resolveAmbiguousName).toHaveBeenCalledWith("my-post");
    expect(getCoin).toHaveBeenCalledWith({ address: COIN });
    expect(updateCoinURISmartWallet).toHaveBeenCalled();
  });

  it("prompts for a new description seeded from the on-chain (IPFS) metadata, not the indexer", async () => {
    // The indexer (getCoin) and IPFS metadata disagree — the prompt default
    // must come from IPFS (the merge base) so accepting it can't persist a
    // stale indexer caption.
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          address: COIN,
          name: "My Post",
          symbol: "POST",
          description: "stale indexer caption",
          tokenUri: "ipfs://bafymeta",
          creatorAddress: SMART_WALLET,
        },
      },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);
    vi.mocked(fetchCoinMetadata).mockResolvedValue({
      ...PREV_METADATA,
      description: "fresh on-chain caption",
    });

    await runEdit([COIN]);

    expect(input).toHaveBeenCalledWith(
      expect.objectContaining({ default: "fresh on-chain caption" }),
    );
    expect(updateCoinURISmartWallet).toHaveBeenCalled();
  });

  it("fetches the current metadata from the coin's tokenUri", async () => {
    await runEdit([COIN, "--description", "hi", "--json"]);
    expect(fetchCoinMetadata).toHaveBeenCalledWith("ipfs://bafymeta");
  });

  it("surfaces a metadata-fetch failure and tracks it", async () => {
    vi.mocked(fetchCoinMetadata).mockRejectedValue(new Error("gateway 500"));
    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to read the coin's current metadata"),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_edit",
      expect.objectContaining({ success: false, stage: "fetch" }),
    );
    expect(updateCoinURISmartWallet).not.toHaveBeenCalled();
  });

  it("warns but proceeds when the indexer can't report the coin's creator", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          address: COIN,
          name: "My Post",
          symbol: "POST",
          description: "old caption",
          tokenUri: "ipfs://bafymeta",
          // creatorAddress omitted — ownership can't be verified client-side.
        },
      },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);

    await runEdit([COIN, "--description", "hi"]); // interactive, so the warning prints

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("couldn't verify this coin's creator"),
    );
    expect(updateCoinURISmartWallet).toHaveBeenCalled();
  });

  it("records a success analytics event", async () => {
    await runEdit([COIN, "--description", "hi", "--json"]);
    expect(track).toHaveBeenCalledWith(
      "cli_edit",
      expect.objectContaining({
        coin: COIN,
        success: true,
        edited_description: true,
        edited_image: false,
        tx_hash: TX_HASH,
      }),
    );
  });

  it("errors when nothing to edit in --json mode, before any network call", async () => {
    await expect(runEdit([COIN, "--json"])).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Nothing to edit"),
    );
    // Fail-fast: the guard fires before the getCoin round-trip.
    expect(getCoin).not.toHaveBeenCalled();
    expect(updateCoinURISmartWallet).not.toHaveBeenCalled();
  });

  it("errors when no identifier is given", async () => {
    await expect(runEdit(["--json"])).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Missing coin to edit"),
    );
  });

  it("errors when no API key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined);
    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("API key is required"),
    );
  });

  it("errors with setup guidance when no wallet is configured", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No wallet configured"),
    );
  });

  it("errors when the coin can't be found", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: null },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);
    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No coin found at"),
    );
  });

  it("refuses to edit a coin created by someone else", async () => {
    const other = `0x${"9".repeat(40)}`;
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          address: COIN,
          name: "Someone Else's Post",
          symbol: "POST",
          description: "",
          tokenUri: "ipfs://bafymeta",
          creatorAddress: other,
        },
      },
    } as unknown as Awaited<ReturnType<typeof getCoin>>);

    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("only edit a coin you created"),
    );
    expect(updateCoinURISmartWallet).not.toHaveBeenCalled();
  });

  it("errors when the new image file is missing", async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    await expect(
      runEdit([COIN, "--image", "./missing.png", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Image file not found"),
    );
  });

  it("errors on an unsupported image type", async () => {
    await expect(
      runEdit([COIN, "--image", "./notes.txt", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Unsupported image type"),
    );
  });

  it("surfaces an on-chain failure and tracks it", async () => {
    vi.mocked(updateCoinURISmartWallet).mockRejectedValue(
      new Error("execution reverted"),
    );
    await expect(
      runEdit([COIN, "--description", "hi", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to edit coin"),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_edit",
      expect.objectContaining({ success: false, stage: "update" }),
    );
  });

  it("exits cleanly when the user declines the confirmation", async () => {
    vi.mocked(confirm).mockResolvedValue(false);
    await expect(runEdit([COIN, "--description", "hi"])).rejects.toThrow(
      "process.exit(0)",
    );
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
    expect(updateCoinURISmartWallet).not.toHaveBeenCalled();
  });
});
