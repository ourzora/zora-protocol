REL_BASE=.

ERC1155_ARTIFACTS_PATH=$REL_BASE/node_modules/@zoralabs/zora-1155-contracts/abis

get_contract_abi () {
  node -e 'var fs = require("fs");console.log(JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1])), null, 2))' $1/$2.json > $REL_BASE/graph-abis/$2.json
}

# 1155 creator impl contracts
get_contract_abi $ERC1155_ARTIFACTS_PATH 'Zora1155'

# 1155 creator factory contracts
get_contract_abi $ERC1155_ARTIFACTS_PATH 'Zora1155Factory'

# minters 1155
get_contract_abi $ERC1155_ARTIFACTS_PATH 'ZoraCreatorRedeemMinterStrategy'
get_contract_abi $ERC1155_ARTIFACTS_PATH 'Zora1155PremintExecutor'
