import { spawn } from "node:child_process";
import { join } from "path";
import { test } from "vitest";
import {
  PublicClient,
  TestClient,
  WalletClient,
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
} from "viem";
import { foundry } from "viem/chains";

export interface AnvilViemClientsTest {
  viemClients: {
    walletClient: WalletClient;
    publicClient: PublicClient;
    testClient: TestClient;
  };
}

async function waitForAnvilInit(anvil: any) {
  return new Promise((resolve) => {
    anvil.stdout.once("data", () => {
      resolve(true);
    });
  });
}

export const anvilTest = test.extend<AnvilViemClientsTest>({
  viemClients: async ({ task }, use) => {
    console.log("setting up clients for ", task.name);
    const port = Math.floor(Math.random() * 2000) + 4000;
    const anvil = spawn(
      "anvil",
      [
        "--port",
        `${port}`,
        "--fork-url",
        "https://rpc.zora.co/",
        "--fork-block-number",
        "6133407",
        "--chain-id",
        "31337",
      ],
      {
        cwd: join(__dirname, ".."),
        killSignal: "SIGINT",
      },
    );
    const anvilHost = `http://0.0.0.0:${port}`;
    await waitForAnvilInit(anvil);

    const chain = {
      ...foundry,
    };

    const walletClient = createWalletClient({
      chain,
      transport: http(anvilHost),
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
      publicClient,
      walletClient,
      testClient,
    });

    // clean up function, called once after all tests run
    anvil.kill("SIGINT");
  },
});
