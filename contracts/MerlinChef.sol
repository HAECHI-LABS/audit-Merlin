// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "./interface/IMerlinMinter.sol";
import "./interface/IMerlinChef.sol";
import "./interface/IStrategy.sol";

import "./MerlinToken.sol";

contract MerlinChef is IMerlinChef, OwnableUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    MerlinToken public MERLIN;

    /* ========== STATE VARIABLES ========== */

    address[] private _vaultList;
    mapping(address => VaultInfo) vaults;
    mapping(address => mapping(address => UserInfo)) vaultUsers;

    IMerlinMinter public minter;

    uint public startBlock;
    uint public override merlinPerBlock;
    uint public override totalAllocPoint;

    /* ========== MODIFIERS ========== */

    modifier onlyVaults {
        require(vaults[msg.sender].token != address(0), "MerlinChef: caller is not on the vault");
        _;
    }

    modifier updateRewards(address vault) {
        VaultInfo storage vaultInfo = vaults[vault];
        if (block.number > vaultInfo.lastRewardBlock) {
            uint tokenSupply = tokenSupplyOf(vault);
            if (tokenSupply > 0) {
                uint multiplier = timeMultiplier(vaultInfo.lastRewardBlock, block.number);
                uint rewards = multiplier.mul(merlinPerBlock).mul(vaultInfo.allocPoint).div(totalAllocPoint);
                vaultInfo.accMerlinPerShare = vaultInfo.accMerlinPerShare.add(rewards.mul(1e12).div(tokenSupply));
            }
            vaultInfo.lastRewardBlock = block.number;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event NotifyDeposited(address indexed user, address indexed vault, uint amount);
    event NotifyWithdrawn(address indexed user, address indexed vault, uint amount);
    event MerlinRewardPaid(address indexed user, address indexed vault, uint amount);

    /* ========== INITIALIZER ========== */

    function initialize(uint _startBlock, uint _merlinPerBlock, address _merlinToken) external initializer {
        __Ownable_init();

        MERLIN = MerlinToken(_merlinToken);

        startBlock = _startBlock;
        merlinPerBlock = _merlinPerBlock;
    }

    /* ========== VIEWS ========== */

    function timeMultiplier(uint from, uint to) public pure returns (uint) {
        return to.sub(from);
    }

    function tokenSupplyOf(address vault) public view returns (uint) {
        return IStrategy(vault).totalSupply();
    }

    function vaultInfoOf(address vault) external view override returns (VaultInfo memory) {
        return vaults[vault];
    }

    function vaultUserInfoOf(address vault, address user) external view override returns (UserInfo memory) {
        return vaultUsers[vault][user];
    }

    function pendingMerlin(address vault, address user) external view override returns (uint) {
        UserInfo storage userInfo = vaultUsers[vault][user];
        VaultInfo storage vaultInfo = vaults[vault];

        uint accMerlinPerShare = vaultInfo.accMerlinPerShare;
        uint tokenSupply = tokenSupplyOf(vault);
        if (block.number > vaultInfo.lastRewardBlock && tokenSupply > 0) {
            uint multiplier = timeMultiplier(vaultInfo.lastRewardBlock, block.number);
            uint merlinRewards = multiplier.mul(merlinPerBlock).mul(vaultInfo.allocPoint).div(totalAllocPoint);
            accMerlinPerShare = accMerlinPerShare.add(merlinRewards.mul(1e12).div(tokenSupply));
        }
        return userInfo.pending.add(userInfo.balance.mul(accMerlinPerShare).div(1e12).sub(userInfo.rewardPaid));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addVault(address vault, address token, uint allocPoint) external onlyOwner {
        require(vaults[vault].token == address(0), "MerlinChef: vault is already set");
        bulkUpdateRewards();

        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        vaults[vault] = VaultInfo(token, allocPoint, lastRewardBlock, 0);
        _vaultList.push(vault);
    }

    function updateVault(address vault, uint allocPoint) external onlyOwner {
        require(vaults[vault].token != address(0), "MerlinChef: vault must be set");
        bulkUpdateRewards();

        uint lastAllocPoint = vaults[vault].allocPoint;
        if (lastAllocPoint != allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(lastAllocPoint).add(allocPoint);
        }
        vaults[vault].allocPoint = allocPoint;
    }

    function setMinter(address _minter) external onlyOwner {
        require(address(minter) == address(0), "MerlinChef: setMinter only once");
        minter = IMerlinMinter(_minter);
    }

    function setMerlinPerBlock(uint _merlinPerBlock) external onlyOwner {
        bulkUpdateRewards();
        merlinPerBlock = _merlinPerBlock;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function notifyDeposited(address user, uint amount) external override onlyVaults updateRewards(msg.sender) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12).sub(userInfo.rewardPaid);
        userInfo.pending = userInfo.pending.add(pending);
        userInfo.balance = userInfo.balance.add(amount);
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12);
        emit NotifyDeposited(user, msg.sender, amount);
    }

    function notifyWithdrawn(address user, uint amount) external override onlyVaults updateRewards(msg.sender) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12).sub(userInfo.rewardPaid);
        userInfo.pending = userInfo.pending.add(pending);
        userInfo.balance = userInfo.balance.sub(amount);
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12);
        emit NotifyWithdrawn(user, msg.sender, amount);
    }

    function safeMerlinTransfer(address user) external override onlyVaults updateRewards(msg.sender) returns (uint) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12).sub(userInfo.rewardPaid);
        uint amount = userInfo.pending.add(pending);
        userInfo.pending = 0;
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accMerlinPerShare).div(1e12);

        minter.mint(amount);
        minter.safeMerlinTransfer(user, amount);
        emit MerlinRewardPaid(user, msg.sender, amount);
        return amount;
    }

    function bulkUpdateRewards() public {
        for (uint idx = 0; idx < _vaultList.length; idx++) {
            if (_vaultList[idx] != address(0) && vaults[_vaultList[idx]].token != address(0)) {
                updateRewardsOf(_vaultList[idx]);
            }
        }
    }

    function updateRewardsOf(address vault) public updateRewards(vault) {
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */
    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(MERLIN), "MerlinChef: cannot recover MERLIN token");
        IBEP20(_token).safeTransfer(owner(), amount);
    }
}

