import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address, type PrivateKeyAccount } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
vi.mock("@inquirer/input");
vi.mock("@inquirer/select");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/wallet.js");
vi.mock("../lib/analytics.js");
vi.mock("node:fs", () => ({
  existsSync: vi.fn(),
  readFileSync: vi.fn(),
}));
vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  CreateConstants: {
    ContentCoinCurrencies: {
      CREATOR_COIN: "CREATOR_COIN",
      ZORA: "ZORA",
      ETH: "ETH",
      CREATOR_COIN_OR_ZORA: "CREATOR_COIN_OR_ZORA",
    },
  },
  createMetadataBuilder: vi.fn(),
  createZoraUploaderForCreator: vi.fn(),
  createCoin: vi.fn(),
  createCoinSmartWallet: vi.fn(),
}));

import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import select from "@inquirer/select";
import { existsSync, readFileSync } from "node:fs";
import {
  createCoin,
  createCoinSmartWallet,
  createMetadataBuilder,
  createZoraUploaderForCreator,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import type { SmartWalletAccount } from "../lib/account/index.js";
import { createCommand } from "./create.js";

const ACCOUNT_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const SMART_WALLET_ADDRESS =
  "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01" as Address;
const COIN_ADDRESS = "0x1234567890abcdef1234567890abcdef12345678" as Address;
const TX_HASH =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" as const;

function runCreate(args: string[]) {
  const program = createProgram(createCommand);
  return program.parseAsync(["create", ...args], { from: "user" });
}

function runCreateJson(args: string[]) {
  const program = createProgram(createCommand);
  return program.parseAsync(["create", ...args, "--json"], { from: "user" });
}

describe("create command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {};
  const walletClient = {};
  const bundlerClient = { account: { address: SMART_WALLET_ADDRESS } };

  const metadataBuilder = {
    withName: vi.fn().mockReturnThis(),
    withSymbol: vi.fn().mockReturnThis(),
    withImage: vi.fn().mockReturnThis(),
    withDescription: vi.fn().mockReturnThis(),
    upload: vi.fn(),
  };

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(select).mockResolvedValue("ZORA");

    vi.mocked(existsSync).mockReturnValue(true);
    vi.mocked(readFileSync).mockReturnValue(Buffer.from("fake-image-bytes"));

    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: ACCOUNT_ADDRESS } as PrivateKeyAccount,
      smartWalletAccount: undefined,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);

    metadataBuilder.withName.mockReturnThis();
    metadataBuilder.withSymbol.mockReturnThis();
    metadataBuilder.withImage.mockReturnThis();
    metadataBuilder.withDescription.mockReturnThis();
    metadataBuilder.upload.mockResolvedValue({
      createMetadataParameters: {
        name: "My Coin",
        symbol: "MYC",
        metadata: { type: "RAW_URI", uri: "ipfs://metadata" },
      },
    });
    vi.mocked(createMetadataBuilder).mockReturnValue(
      metadataBuilder as unknown as ReturnType<typeof createMetadataBuilder>,
    );
    vi.mocked(createZoraUploaderForCreator).mockReturnValue({} as any);

    vi.mocked(createCoin).mockResolvedValue({
      hash: TX_HASH,
      address: COIN_ADDRESS,
    } as unknown as Awaited<ReturnType<typeof createCoin>>);
    vi.mocked(createCoinSmartWallet).mockResolvedValue({
      hash: TX_HASH,
      address: COIN_ADDRESS,
    } as unknown as Awaited<ReturnType<typeof createCoinSmartWallet>>);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  const FULL_ARGS = [
    "--name",
    "My Coin",
    "--symbol",
    "MYC",
    "--description",
    "A test coin",
    "--image",
    "/tmp/image.png",
    "--yes",
  ];

  // --- Validation ---

  it("exits with error when no API key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined);
    await expect(runCreate(FULL_ARGS)).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("API key is required"),
    );
  });

  it("exits with error for an invalid currency", async () => {
    await expect(
      runCreate([...FULL_ARGS, "--currency", "DOGE"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --currency value"),
    );
  });

  it("exits with error when the image file does not exist", async () => {
    vi.mocked(existsSync).mockReturnValue(false);
    await expect(runCreate(FULL_ARGS)).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Image file not found"),
    );
  });

  it("exits with error for an unsupported image type", async () => {
    await expect(
      runCreate([
        "--name",
        "My Coin",
        "--symbol",
        "MYC",
        "--image",
        "/tmp/image.bmp",
        "--yes",
      ]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Unsupported image type"),
    );
  });

  it("exits with error for a ticker that is too long", async () => {
    await expect(
      runCreate([
        "--name",
        "My Coin",
        "--symbol",
        "WAYTOOLONGTICKERVALUE1",
        "--image",
        "/tmp/image.png",
        "--yes",
      ]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("20 characters or fewer"),
    );
  });

  it("exits with error for a ticker with disallowed characters", async () => {
    await expect(
      runCreate([
        "--name",
        "My Coin",
        "--symbol",
        "MY COIN",
        "--image",
        "/tmp/image.png",
        "--yes",
      ]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("letters and numbers"),
    );
  });

  // --- Prompting ---

  it("prompts for missing fields", async () => {
    vi.mocked(input)
      .mockResolvedValueOnce("Prompted Coin") // name
      .mockResolvedValueOnce("PRM") // symbol
      .mockResolvedValueOnce("") // description
      .mockResolvedValueOnce("/tmp/image.png"); // image

    await runCreate(["--yes"]);

    expect(input).toHaveBeenCalledTimes(4);
    expect(createCoin).toHaveBeenCalledOnce();
  });

  it("does not prompt in --json mode, errors on missing field", async () => {
    await expect(runCreateJson(["--symbol", "MYC"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(input).not.toHaveBeenCalled();
  });

  // --- EOA path ---

  it("creates a coin via the EOA path", async () => {
    await runCreate(FULL_ARGS);

    expect(createZoraUploaderForCreator).toHaveBeenCalledWith(ACCOUNT_ADDRESS);
    expect(createCoin).toHaveBeenCalledOnce();
    expect(createCoinSmartWallet).not.toHaveBeenCalled();

    const call = vi.mocked(createCoin).mock.calls[0]![0];
    expect(call.call.creator).toBe(ACCOUNT_ADDRESS);
    expect(call.call.currency).toBe("ZORA");
  });

  // --- Currency selection ---

  it("prompts for currency with a select when --currency is omitted", async () => {
    vi.mocked(select).mockResolvedValue("CREATOR_COIN");

    await runCreate(FULL_ARGS);

    expect(select).toHaveBeenCalledOnce();
    expect(vi.mocked(select).mock.calls[0]![0]).toMatchObject({
      message: "Currency (paired with)",
    });
    const call = vi.mocked(createCoin).mock.calls[0]![0];
    expect(call.call.currency).toBe("CREATOR_COIN");
  });

  it("does not prompt for currency when --currency is provided", async () => {
    await runCreate([...FULL_ARGS, "--currency", "eth"]);

    expect(select).not.toHaveBeenCalled();
    const call = vi.mocked(createCoin).mock.calls[0]![0];
    expect(call.call.currency).toBe("ETH");
  });

  it("does not prompt for currency in --json mode, defaults to ZORA", async () => {
    await runCreateJson([
      "--name",
      "My Coin",
      "--symbol",
      "MYC",
      "--image",
      "/tmp/image.png",
    ]);

    expect(select).not.toHaveBeenCalled();
    const call = vi.mocked(createCoin).mock.calls[0]![0];
    expect(call.call.currency).toBe("ZORA");
  });

  // --- Smart wallet path ---

  it("prefers the smart wallet path (via bundler) when one is configured", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: ACCOUNT_ADDRESS } as PrivateKeyAccount,
      smartWalletAccount: {
        address: SMART_WALLET_ADDRESS,
      } as SmartWalletAccount,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
      bundlerClient,
    } as unknown as ReturnType<typeof createClients>);

    await runCreate(FULL_ARGS);

    expect(createZoraUploaderForCreator).toHaveBeenCalledWith(
      SMART_WALLET_ADDRESS,
    );
    expect(createCoinSmartWallet).toHaveBeenCalledOnce();
    expect(createCoin).not.toHaveBeenCalled();

    const arg = vi.mocked(createCoinSmartWallet).mock.calls[0]![0];
    expect(arg.call.creator).toBe(SMART_WALLET_ADDRESS);
    // Smart wallet path drives the bundler, not the wallet client.
    expect(arg.bundlerClient).toBe(bundlerClient);
  });

  it("errors when a smart wallet is configured but no bundler client is available", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: ACCOUNT_ADDRESS } as PrivateKeyAccount,
      smartWalletAccount: {
        address: SMART_WALLET_ADDRESS,
      } as SmartWalletAccount,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    // createClients default mock returns no bundlerClient.
    await expect(runCreate(FULL_ARGS)).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("bundler client"),
    );
    expect(createCoinSmartWallet).not.toHaveBeenCalled();
  });

  // --- Confirmation ---

  it("aborts when the user declines confirmation", async () => {
    vi.mocked(confirm).mockResolvedValue(false);
    await expect(
      runCreate([
        "--name",
        "My Coin",
        "--symbol",
        "MYC",
        "--image",
        "/tmp/i.png",
      ]),
    ).rejects.toThrow("process.exit(0)");
    expect(createCoin).not.toHaveBeenCalled();
  });

  // --- JSON output ---

  it("outputs JSON when --json is set", async () => {
    await runCreateJson([
      "--name",
      "My Coin",
      "--symbol",
      "MYC",
      "--image",
      "/tmp/image.png",
    ]);

    const output = parsedOutput();
    expect(output).toMatchObject({
      action: "create",
      name: "My Coin",
      symbol: "MYC",
      currency: "ZORA",
      address: COIN_ADDRESS,
      tx: TX_HASH,
      walletType: "eoa",
    });
  });

  it("omits the description from the builder when not provided", async () => {
    await runCreate([
      "--name",
      "My Coin",
      "--symbol",
      "MYC",
      "--image",
      "/tmp/image.png",
      "--yes",
    ]);
    expect(metadataBuilder.withDescription).not.toHaveBeenCalled();
  });
});
