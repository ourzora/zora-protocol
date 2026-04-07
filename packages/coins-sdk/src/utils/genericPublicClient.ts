import { PublicClient as VanillaPublicClient } from "viem";

// A bit messy for now but it works with peerdeps.
// TODO: Make this a more clear type.
export type GenericPublicClient = VanillaPublicClient<any, any, any, any>;
