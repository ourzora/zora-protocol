import { readdirSync, readFileSync, writeFileSync } from 'fs';
import prettier from 'prettier';

// Reads all the chain configs in ./chainConfigs folder, and bundles them into a typescript 
// definition that looks like:
// export const chainConfigs = {
//  [chainId]: {
//    ...chainConfig
//  }
//}
function makeConfig() {
  // read all files in the chainConfigs folder
  const files = readdirSync('chainConfigs');

  const byProperty = {};

  files.forEach(async(fileName) => {
    // this is the properties for the chain id
    const chainConfig = JSON.parse(readFileSync(`chainConfigs/${fileName}`));
    const chainId = fileName.split('.')[0];

    Object.entries(chainConfig).forEach(([key, value]) => {
      byProperty[key] = {
        ...byProperty[key],
        [chainId]: value
      }
    });
  });

  return `export const chainConfigs = ${JSON.stringify(byProperty)};`
}

async function bundleChainConfigs() {
  const configString = makeConfig();

  const prettierConfig = await prettier.resolveConfig('../.prettierrc.js');

  const formatted = prettier.format(configString, prettierConfig);

  writeFileSync('./package/chainConfigs.ts',  formatted);
}

await bundleChainConfigs();
