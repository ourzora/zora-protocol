import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { getAddress } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/wallet.js");
// Factory (not auto) so the real config.ts top-level code never runs.
vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  getSmartWalletAddress: vi.fn(),
  getApiKey: vi.fn(),
  getBudget: vi.fn(),
  saveBudget: vi.fn(),
  getAnalyticsId: vi.fn(),
  saveAnalyticsId: vi.fn(),
}));
vi.mock("../lib/analytics.js");
vi.mock("@inquirer/confirm");
vi.mock("@inquirer/input");
vi.mock("@x402/fetch");
// Keep parseAcceptsInput + the header/network constants real; stub the pieces
// that would otherwise sign or hit the network.
vi.mock("../lib/x402/index.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../lib/x402/index.js")>();
  return {
    ...actual,
    resolvePayment: vi.fn(),
    signPayment: vi.fn(),
    createX402Client: vi.fn(),
  };
});

import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import { decodePaymentResponseHeader, wrapFetchWithPayment } from "@x402/fetch";
import { track } from "../lib/analytics.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import { resolvePayment, signPayment } from "../lib/x402/index.js";
import { payCommand } from "./pay.js";

const ACCOUNT_ADDRESS = getAddress(
  "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
);
const USDC = getAddress("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
const PAY_TO = getAddress("0xAbCdEf0123456789AbCdEf0123456789AbCdEf01");

const ACCEPTS = JSON.stringify({
  x402Version: 2,
  resource: { url: "https://api.example.com/data", description: "Test" },
  accepts: [
    {
      scheme: "exact",
      network: "eip155:8453",
      amount: "1000000",
      asset: USDC,
      payTo: PAY_TO,
      maxTimeoutSeconds: 60,
      extra: { name: "USD Coin", version: "2" },
    },
  ],
});

function selectedResult() {
  return {
    kind: "selected" as const,
    requirement: {
      scheme: "exact",
      network: "eip155:8453" as `${string}:${string}`,
      amount: "1000000",
      asset: USDC,
      payTo: PAY_TO,
      maxTimeoutSeconds: 60,
      extra: {},
    },
    balance: 5_000_000n,
  };
}

const SIGNED = { header: "c2lnbmVkLXBheW1lbnQ=", payload: {} as never };

function runPay(args: string[]) {
  return createProgram(payCommand).parseAsync(["pay", ...args], {
    from: "user",
  });
}
function runPayJson(args: string[]) {
  return createProgram(payCommand).parseAsync(["pay", ...args, "--json"], {
    from: "user",
  });
}

describe("pay command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  const createdPaths: string[] = [];

  const publicClient = { readContract: vi.fn() };

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });
    vi.mocked(confirm).mockResolvedValue(true);

    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: ACCOUNT_ADDRESS } as never,
      smartWalletAccount: undefined,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(input).mockResolvedValue("");
    publicClient.readContract.mockImplementation(
      async ({ functionName }: { functionName: string }) =>
        functionName === "decimals"
          ? 6
          : functionName === "symbol"
            ? "USDC"
            : 0n,
    );
  });

  afterEach(() => {
    // Clean up any temp files the command wrote.
    for (const p of createdPaths.splice(0)) {
      try {
        rmSync(dirname(p), { recursive: true, force: true });
      } catch {
        /* ignore */
      }
    }
    vi.restoreAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  /** A wrapped-fetch stub that returns a controlled Response. */
  function stubFetch(body: BodyInit, init: ResponseInit) {
    vi.mocked(wrapFetchWithPayment).mockReturnValue(
      (async () => new Response(body, init)) as typeof fetch,
    );
  }

  // --- Mode selection / validation ---

  it("errors when neither --accepts nor --url is given", async () => {
    await expect(runPayJson([])).rejects.toThrow("process.exit(1)");
    expect(parsedOutput().error).toMatch(/--accepts.*--url|--url.*--accepts/);
  });

  it("errors when both --accepts and --url are given", async () => {
    await expect(
      runPayJson(["--accepts", ACCEPTS, "--url", "https://x.test"]),
    ).rejects.toThrow("process.exit(1)");
    expect(parsedOutput().error).toMatch(/cannot be used together/);
  });

  it("rejects a non-positive --max-value", async () => {
    await expect(
      runPayJson(["--accepts", ACCEPTS, "--max-value", "0"]),
    ).rejects.toThrow("process.exit(1)");
    expect(parsedOutput().error).toMatch(/--max-value/);
  });

  it("rejects a non-address --asset", async () => {
    await expect(
      runPayJson(["--accepts", ACCEPTS, "--asset", "not-an-address"]),
    ).rejects.toThrow("process.exit(1)");
    expect(parsedOutput().error).toMatch(/--asset/);
  });

  // --- Builder mode (--accepts) ---

  describe("builder mode", () => {
    it("resolves, signs, and outputs the PAYMENT-SIGNATURE header in JSON", async () => {
      vi.mocked(resolvePayment).mockResolvedValue(selectedResult());
      vi.mocked(signPayment).mockResolvedValue(SIGNED);

      await runPayJson(["--accepts", ACCEPTS]);

      const out = parsedOutput();
      expect(out.action).toBe("pay");
      expect(out.mode).toBe("build");
      expect(out.headerName).toBe("PAYMENT-SIGNATURE");
      expect(out.header).toBe("c2lnbmVkLXBheW1lbnQ=");
      expect(out.requirement.asset).toBe(USDC);
      expect(out.requirement.amount).toBe("1000000");
      expect(out.requirement.amountFormatted).toBe("1");
      expect(out.requirement.symbol).toBe("USDC");
      expect(track).toHaveBeenCalledWith(
        "cli_pay",
        expect.objectContaining({ mode: "build", success: true }),
      );
    });

    it("errors and tracks failure when nothing is payable (never signs)", async () => {
      vi.mocked(resolvePayment).mockResolvedValue({
        kind: "none",
        reason: "No payable entry: insufficient balance.",
      });

      await expect(runPayJson(["--accepts", ACCEPTS])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(parsedOutput().error).toMatch(/No payable entry/);
      expect(signPayment).not.toHaveBeenCalled();
      expect(track).toHaveBeenCalledWith(
        "cli_pay",
        expect.objectContaining({ mode: "build", success: false }),
      );
    });

    it("errors on unparseable --accepts input", async () => {
      await expect(
        runPayJson(["--accepts", "this is not json"]),
      ).rejects.toThrow("process.exit(1)");
      expect(resolvePayment).not.toHaveBeenCalled();
    });

    it("does not sign when the user declines the confirmation", async () => {
      vi.mocked(resolvePayment).mockResolvedValue(selectedResult());
      vi.mocked(signPayment).mockResolvedValue(SIGNED);
      vi.mocked(confirm).mockResolvedValue(false);

      // Interactive (no --json, no --yes) → preview + confirm → declined.
      await expect(runPay(["--accepts", ACCEPTS])).rejects.toThrow(
        "process.exit(0)",
      );
      // The critical guarantee: no signed authorization is ever created.
      expect(signPayment).not.toHaveBeenCalled();
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Aborted"));
    });
  });

  // --- Round-trip mode (--url) ---

  describe("fetch mode", () => {
    it("inlines a text body and also saves it to a temp file", async () => {
      stubFetch(JSON.stringify({ price: 42 }), {
        status: 200,
        headers: {
          "content-type": "application/json",
          "PAYMENT-RESPONSE": "settle-header",
        },
      });
      vi.mocked(decodePaymentResponseHeader).mockReturnValue({
        success: true,
        transaction: "0xtx",
        network: "eip155:8453",
        payer: ACCOUNT_ADDRESS,
      } as never);

      await runPayJson(["--url", "https://api.example.com/price"]);

      const out = parsedOutput();
      expect(out.mode).toBe("fetch");
      expect(out.status).toBe(200);
      expect(out.contentType).toBe("application/json");
      expect(out.encoding).toBe("utf8");
      expect(out.body).toEqual({ price: 42 });
      expect(out.paid).toBe(true);
      expect(out.settlement.transaction).toBe("0xtx");
      expect(typeof out.savedTo).toBe("string");
      createdPaths.push(out.savedTo);
      // The temp file holds the raw body.
      expect(readFileSync(out.savedTo, "utf8")).toBe('{"price":42}');
    });

    it("references a binary body by file path without inlining it", async () => {
      const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
      stubFetch(png, {
        status: 200,
        headers: { "content-type": "image/png" },
      });

      await runPayJson(["--url", "https://api.example.com/image"]);

      const out = parsedOutput();
      expect(out.encoding).toBe("binary");
      expect(out.contentType).toBe("image/png");
      expect(out.body).toBeUndefined();
      expect(out.bytes).toBe(png.length);
      expect(out.savedTo).toMatch(/zora-x402-.*\.png$/);
      createdPaths.push(out.savedTo);
      expect(new Uint8Array(readFileSync(out.savedTo))).toEqual(png);
    });

    it("writes to --output and reports it as savedTo", async () => {
      const dir = (await import("node:fs")).mkdtempSync(
        (await import("node:os")).tmpdir() + "/pay-test-",
      );
      const target = `${dir}/out.bin`;
      createdPaths.push(target);
      stubFetch(new Uint8Array([1, 2, 3]), {
        status: 200,
        headers: { "content-type": "application/octet-stream" },
      });

      await runPayJson([
        "--url",
        "https://api.example.com/blob",
        "--output",
        target,
      ]);

      const out = parsedOutput();
      expect(out.savedTo).toBe(target);
      expect(out.bytes).toBe(3);
      expect(new Uint8Array(readFileSync(target))).toEqual(
        new Uint8Array([1, 2, 3]),
      );
    });

    it("errors, tracks, and suggests on a failed x402 request", async () => {
      vi.mocked(wrapFetchWithPayment).mockReturnValue((async () => {
        throw new Error("insufficient funds");
      }) as typeof fetch);

      await expect(
        runPayJson(["--url", "https://api.example.com/paid"]),
      ).rejects.toThrow("process.exit(1)");
      expect(parsedOutput().error).toMatch(/x402 request failed/);
      expect(track).toHaveBeenCalledWith(
        "cli_pay",
        expect.objectContaining({ mode: "fetch", success: false }),
      );
    });
  });
});
