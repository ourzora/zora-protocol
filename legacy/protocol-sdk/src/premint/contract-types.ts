import {
  ContractCreationConfig,
  PremintConfigVersion as PremintConfigVersionOrig,
} from "@zoralabs/protocol-deployments";
import { Address } from "viem";

export enum PremintConfigVersion {
  V1 = PremintConfigVersionOrig.V1,
  V2 = PremintConfigVersionOrig.V2,
  V3 = PremintConfigVersionOrig.V3,
}

export type ContractCreationConfigWithOptionalAdditionalAdmins = Omit<
  ContractCreationConfig,
  "additionalAdmins"
> & {
  /** Optional: if there are additional admins accounts that should be added as contract wide admins upon contract creation. */
  additionalAdmins?: Address[];
};

export type ContractCreationConfigAndAddress = {
  /** Parameters for creating the contract for new premints. */
  collection?: ContractCreationConfigWithOptionalAdditionalAdmins;
  /** Premint collection address */
  collectionAddress: Address;
};

export type ContractCreationConfigOrAddress =
  | {
      /** Parameters for creating the contract for new premints. */
      contract: ContractCreationConfigWithOptionalAdditionalAdmins;
      contractAddress?: undefined;
    }
  | {
      contract?: undefined;
      /** Premint collection address */
      contractAddress: Address;
    };
