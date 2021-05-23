// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/PoolConstant.sol";
import "./IVaultController.sol";

struct Profit {
    uint usd;
    uint merlin;
    uint bnb;
}

struct APY {
    uint usd;
    uint merlin;
    uint bnb;
}

struct UserInfo {
    uint balance;
    uint principal;
    uint available;
    Profit profit;
    uint poolTVL;
    APY poolAPY;
}


interface IStrategy is IVaultController {
    function deposit(uint _amount) external;
    function depositAll() external;
    function withdraw(uint256 _amount) external;    // MERLIN STAKING POOL ONLY
    function withdrawAll() external;
    function getReward() external;                  // MERLIN STAKING POOL ONLY
    function harvest() external;

    function totalSupply() external view returns (uint);
    function balance() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function sharesOf(address account) external view returns (uint);
    function principalOf(address account) external view returns (uint);
    function earned(address account) external view returns (uint);
    function withdrawableBalanceOf(address account) external view returns (uint);   // MERLIN STAKING POOL ONLY
    function priceShare() external view returns(uint);

    /* ========== Strategy Information ========== */

    // function pid() external view returns (uint);
    function poolType() external view returns (PoolConstant.PoolTypes);
    function depositedAt(address account) external view returns (uint);
    function rewardsToken() external view returns (address);

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 withdrawalFee);
    event ProfitPaid(address indexed user, uint256 profit, uint256 performanceFee);
    event MerlinPaid(address indexed user, uint256 profit, uint256 performanceFee);
    event Harvested(uint256 profit);
}
