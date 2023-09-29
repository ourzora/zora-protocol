# forge script on 999 failed with error:
# We haven't found any matching bytecode for the following contracts: 
# [0x49e85797dc499b9132433a62f63ef80e76c07865, 0x71524d1d958f9014848c69511c685008e0caef60, 0x561798076ab88b3c760614fdcb948fff4584a9ff]
# 0x49e is the 
#

# verify factory proxy Zora1155Factory
forge verify-contract 0x777777267FA8D1C26EF7A2dffb33A290464D1b4B --chain 777777 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf Zora1155Factory
# forge verify-contract 0x49e85797dc499b9132433a62f63ef80e76c07865 --chain 777777 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf ZoraCreator1155Impl
#forge verify-contract 0x6E2AbBcd82935bFC68A1d5d2c96372b13b65eD9C --chain 777777 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf Zora1155PremintExecutorImpl
#forge verify-contract 0x6E2AbBcd82935bFC68A1d5d2c96372b13b65eD9C --chain 777777 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf ZoraCreator1155PremintExecutorImpl
# forge verify-contract 0x8E024a6e8E9c1cbC5BfcC73e87409a6D98b3425d --chain 777777 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf Zora1155