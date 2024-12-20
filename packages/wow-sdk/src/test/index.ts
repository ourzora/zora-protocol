import { spawn } from "node:child_process";
import { join } from "path";
import { test } from "vitest";
import {
  Account,
  Address,
  Chain,
  PublicClient,
  SimulateContractParameters,
  SimulateContractReturnType,
  TransactionReceipt,
  Transport,
  WalletClient,
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
} from "viem";
import { foundry } from "viem/chains";
import { AnvilForkSettings, AnvilViemClients } from "./types";
import { retries } from "./utils/http";
import { privateKeyToAccount } from "viem/accounts";
import { SupportedChain } from "../types";

async function waitForAnvilInit(anvil: any) {
  return new Promise((resolve, reject) => {
    anvil.stderr.once("data", (data: Buffer) => {
      reject(data.toString("utf-8"));
    });
    anvil.stdout.once("data", () => {
      resolve(true);
    });
  });
}

export const makeAnvilTest = ({
  forkUrl,
  forkBlockNumber,
  anvilChainId = 31337,
}: AnvilForkSettings) =>
  test.extend<{ viemClients: AnvilViemClients }>({
    viemClients: async ({ task }, use) => {
      console.log("setting up clients for", task.name);
      const port = Math.floor(Math.random() * 60000) + 4000;

      const anvil = spawn(
        "anvil",
        [
          "--port",
          `${port}`,
          "--fork-url",
          forkUrl,
          "--fork-block-number",
          `${forkBlockNumber}`,
          "--chain-id",
          anvilChainId.toString(),
        ],
        {
          cwd: join(__dirname, ".."),
          killSignal: "SIGINT",
        },
      );

      const anvilHost = `http://0.0.0.0:${port}`;

      const anvilTestAccount = privateKeyToAccount(
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
      );
      await waitForAnvilInit(anvil);

      const chain: Chain = {
        ...foundry,
        id: anvilChainId,
      };

      const walletClient = createWalletClient({
        chain,
        transport: http(anvilHost),
        account: anvilTestAccount,
      });

      const testClient = createTestClient({
        chain,
        mode: "anvil",
        transport: http(anvilHost),
      });

      const publicClient = createPublicClient({
        chain,
        transport: http(anvilHost),
      });

      await use({
        publicClient: publicClient as PublicClient<Transport, SupportedChain>,
        walletClient,
        testClient,
        chain,
      });

      anvil.kill("SIGINT");
    },
  });

export async function simulateAndWriteContractWithRetries({
  parameters,
  walletClient,
  publicClient,
}: {
  parameters: SimulateContractParameters<any, any, any, any, any, Address>;
  walletClient: WalletClient;
  publicClient: PublicClient<Transport, SupportedChain>;
}) {
  const { request } = await publicClient.simulateContract(parameters);
  return await writeContractWithRetries({
    request,
    walletClient,
    publicClient,
  });
}

export async function waitForTransactionReceiptWithRetries(
  publicClient: PublicClient<Transport, SupportedChain>,
  hash: `0x${string}`,
): Promise<TransactionReceipt> {
  let tryCount = 1;
  const tryFn = async () => {
    if (tryCount > 1) {
      console.log("retrying wait for receipt #", tryCount);
    }
    try {
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") {
        console.log("failed wait #", tryCount);
        tryCount++;
        throw new Error("transaction failed");
      }
      return receipt;
    } catch (e) {
      console.log("failed wait #", tryCount);
      tryCount++;
      throw e;
    }
  };

  return await retries(tryFn, 3, 1000, () => true);
}

export async function writeContractWithRetries({
  request,
  walletClient,
  publicClient,
}: {
  request: SimulateContractReturnType<any, any, any, Chain, Account>["request"];
  walletClient: WalletClient;
  publicClient: PublicClient<Transport, SupportedChain>;
}) {
  const hash = await walletClient.writeContract(request);
  return await waitForTransactionReceiptWithRetries(publicClient, hash);
}

export * from "./types";
