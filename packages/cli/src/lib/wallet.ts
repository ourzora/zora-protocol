import {
  normalizeKey,
  resolveAccount,
  resolveAccounts,
  resolvePrivateKeyAccount,
  resolveSmartWalletAccount,
} from "./account/index.js";
import { createClients } from "./client/index.js";

// this file used to contain all the logic for private key accounts and wallet clients;
// this has been refactored into the account and client modules to support the addition
// of smart wallet accounts and bundler clients
// we re-export these here to avoid having to refactor all the imports in the project
// and keep the resulting PRs manageable and focused
export {
  createClients,
  normalizeKey,
  resolveAccount,
  resolveAccounts,
  resolvePrivateKeyAccount,
  resolveSmartWalletAccount,
};
