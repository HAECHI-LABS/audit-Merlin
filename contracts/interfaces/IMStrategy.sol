// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./IMVaultController.sol";

interface IMStrategy is IMVaultController {
    enum PoolTypes {
        MerlinStake, // no perf fee
        MerlinFlip_deprecated, // deprecated
        CakeStake, FlipToFlip, FlipToCake,
        Merlin, // no perf fee
        MerlinBNB,
        Venus
    }

    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint _amount) external;    // MERL STAKING POOL ONLY
    function withdrawAll() external;
    function getReward() external;                  // MERL STAKING POOL ONLY
    function harvest() external;

    function totalSupply() external view returns (uint);
    function balance() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function sharesOf(address account) external view returns (uint);
    function principalOf(address account) external view returns (uint);
    function earned(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // MERL STAKING POOL ONLY
    function priceShare() external view returns (uint);

    /* ========== Strategy Information ========== */

    function pid() external view returns (uint);
    function poolType() external view returns (PoolTypes);
    function depositedAt(address account) external view returns (uint);
    function rewardsToken() external view returns (address);

    function merlinChef() external view returns (address);
    function rewardRate() external view returns (uint);

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount, uint withdrawalFee);
    event ProfitPaid(address indexed user, uint profit, uint performanceFee);
    event BunnyPaid(address indexed user, uint profit, uint performanceFee);
    event Harvested(uint profit);
}
