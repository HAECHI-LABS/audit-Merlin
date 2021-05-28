// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./legacy/IMStrategyHelper.sol";

interface IMerlinPool {
    struct Profit {
        uint usd;
        uint bunny;
        uint bnb;
    }

    struct APY {
        uint usd;
        uint bunny;
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

    function totalSupply() external view returns (uint256);
    function balance() external view returns (uint);
    function balanceOf(address account) external view returns (uint256);
    function presaleBalanceOf(address account) external view returns (uint256);
    function principalOf(address account) external view returns (uint256);
    function withdrawableBalanceOf(address account) external view returns (uint);
    function profitOf(address account) external view returns (uint _usd, uint _bunny, uint _bnb);
    function tvl() external view returns (uint);
    function apy() external view returns (uint _usd, uint _bunny, uint _bnb);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function getRewardForDuration() external view returns (uint256);
    function deposit(uint256 amount) external;
    function depositAll() external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function getReward() external;
    function harvest() external;
    function info(address account) external view returns (UserInfo memory);
    function setRewardsToken(address _rewardsToken) external;
    function setHelper(IMStrategyHelper _helper) external;
    function setStakePermission(address _address, bool permission) external;
    function stakeTo(uint256 amount, address _to) external;
    function notifyRewardAmount(uint256 reward) external;
    function recoverBEP20(address tokenAddress, uint256 tokenAmount) external;
    function setRewardsDuration(uint256 _rewardsDuration) external;

    function rewardsToken() external view returns (address);
    function stakingToken() external view returns (address);
    function rewardRate() external view returns (uint);
}
