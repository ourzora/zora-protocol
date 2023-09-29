# forge script on 999 failed with error:
# We haven't found any matching bytecode for the following contracts: 
# [0x49e85797dc499b9132433a62f63ef80e76c07865, 0x71524d1d958f9014848c69511c685008e0caef60, 0x561798076ab88b3c760614fdcb948fff4584a9ff]
# 0x49e is the 
#

# verify factory proxy Zora1155Factory
forge verify-contract 0x777777267FA8D1C26EF7A2dffb33A290464D1b4B --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf Zora1155Factory
forge verify-contract 0x49e85797dc499b9132433a62f63ef80e76c07865 --verifier-url $VERIFIER_URL --verifier blockscout --etherscan-api-key asdfasdf ZoraCreator1155Impl