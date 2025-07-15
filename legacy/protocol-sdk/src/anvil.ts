import { spawn } from "node:child_process";
import { join } from "path";
import { test } from "vitest";
import {
  Chain,
  PublicClient,
  TestClient,
  Transport,
  WalletClient,
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
} from "viem";
import { foundry, zora } from "viem/chains";

export interface AnvilViemClientsTest {
  viemClients: {
    walletClient: WalletClient;
    // see https://github.com/wevm/viem/discussions/2282
    publicClient: PublicClient<Transport, Chain>;
    testClient: TestClient;
    chain: Chain;
  };
}

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

export type AnvilTestForkSettings = {
  forkUrl: string;
  forkBlockNumber: number;
  anvilChainId?: number;
};

export const makeAnvilTest = ({
  forkUrl,
  forkBlockNumber,
  anvilChainId = 31337,
}: AnvilTestForkSettings) =>
  test.extend<AnvilViemClientsTest>({
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

      await waitForAnvilInit(anvil);

      const chain: Chain = {
        ...foundry,
        id: anvilChainId,
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
        chain,
      });

      // clean up function, called once after all tests run
      anvil.kill("SIGINT");
    },
  });

export const forkUrls = {
  zoraMainnet: `https://rpc.zora.energy/${process.env.VITE_CONDUIT_KEY}`,
  zoraSepolia: `https://sepolia.rpc.zora.energy/${process.env.VITE_CONDUIT_KEY}`,
  baseMainnet: `https://base-mainnet.g.alchemy.com/v2/${process.env.VITE_ALCHEMY_KEY}`,
};

export const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  forkBlockNumber: 7866332,
  anvilChainId: zora.id,
});
