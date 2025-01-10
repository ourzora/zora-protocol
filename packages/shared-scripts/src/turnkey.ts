import { TurnkeyClient } from "@turnkey/http";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { createAccount } from "@turnkey/viem";

import { fileURLToPath } from "url";
import { dirname } from "path";
import * as path from "path";
import * as dotenv from "dotenv";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, "../.env") });

export const loadTurnkeyAccount = async () => {
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    new ApiKeyStamper({
      apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
      apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
    }),
  );

  // Create the Viem custom account
  return await createAccount({
    client: httpClient,
    organizationId: process.env.TURNKEY_ORGANIZATION_ID!,
    signWith: process.env.TURNKEY_PRIVATE_KEY_ID!,
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: process.env.TURNKEY_TARGET_ADDRESS!,
  });
};
