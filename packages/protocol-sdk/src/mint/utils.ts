import * as semver from "semver";
export const contractSupportsNewMintFunction = (
  contractVersion?: string | null,
) => {
  if (!contractVersion) {
    return false;
  }

  // Try force-convert version format to semver format
  const semVerContractVersion = semver.coerce(contractVersion)?.raw;
  if (!semVerContractVersion) return false;

  return semver.gte(semVerContractVersion, "2.9.0");
};
