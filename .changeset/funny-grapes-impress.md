---
"@zoralabs/zora-1155-contracts": patch
---

ERC20 Minter V2 Changes:
* Adds a flat ETH fee that goes to Zora (currently this fee is 0.000111 ETH but the contract owner can change this fee at any time)
* Reward recipients will still receive ERC20 rewards however this percentage can now be changed at any time by the contract owner 
* Adds an `ERC20MinterConfig` struct which contains `zoraRewardRecipientAddress`, `rewardRecipientPercentage`, and `ethReward`
* Zora Reward Recipient Address can now be changed at any time by the contract owner as well
* `mint` function is now payable
* New functions:
    * `function ethRewardAmount() external view returns (uint256)`
    * `function setERC20MinterConfig(ERC20MinterConfig memory config) external`
    * `function getERC20MinterConfig() external view returns (ERC20MinterConfig memory)`
* New events:
    * `event ERC20MinterConfigSet(ERC20MinterConfig config)`
* Removed events:
    * `event ZoraRewardsRecipientSet(address indexed prevRecipient, address indexed newRecipient)`
    * `event ERC20MinterInitialized(uint256 rewardPercentage)`
