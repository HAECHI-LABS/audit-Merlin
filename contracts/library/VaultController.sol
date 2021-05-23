// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";

import "../interface/IPancakeRouter02.sol";
import "../interface/IPancakePair.sol";
import "../interface/IStrategy.sol";
import "../interface/IMasterChef.sol";
import "../interface/IMerlinMinter.sol";
import "../interface/IMerlinChef.sol";
import "../interface/IVaultController.sol";
import "./PausableUpgradeable.sol";
import "./WhitelistUpgradeable.sol";

abstract contract VaultController is IVaultController, PausableUpgradeable, WhitelistUpgradeable {
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT VARIABLES ========== */
    BEP20 private MERLIN;

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    IBEP20 internal _stakingToken;
    IMerlinMinter internal _minter;
    IMerlinChef internal _merlinChef;

    /* ========== VARIABLE GAP ========== */

    uint256[49] private __gap;

    /* ========== Event ========== */

    event Recovered(address token, uint amount);
    event KeeperChanged(address newKeeper);


    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), 'VaultController: caller is not the owner or keeper');
        _;
    }

    modifier nonContract {
        uint32 size;
        address callerAddress = msg.sender;
        // CAUTION: extcodesize returns 0 if it is called from the constructor of a contract.
        assembly { size := extcodesize(callerAddress) }

        // CAUTION: Vitalik has suggested that developers should “NOT assume that tx.origin will continue to be usable or meaningful.”
        // For the time-being, tx.origin is always an EOA, we know it cannot be a contract 
        require (size == 0 && callerAddress == tx.origin, "only EOA");

        _;
    }

    /* ========== INITIALIZER ========== */

    function __VaultController_init(IBEP20 token, address _merlin) internal initializer {
        __PausableUpgradeable_init();
        __WhitelistUpgradeable_init();

        keeper = 0x793074D9799DC3c6039F8056F1Ba884a73462051;
        _stakingToken = token;
        MERLIN = BEP20(_merlin);
    }

    /* ========== VIEWS FUNCTIONS ========== */

    function minter() external view override returns (address) {
        return canMint() ? address(_minter) : address(0);
    }

    function canMint() internal view returns (bool) {
        return address(_minter) != address(0) && _minter.isMinter(address(this));
    }

    function merlinChef() external view returns (address) {
        return address(_merlinChef);
    }

    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), 'VaultController: invalid keeper address');
        keeper = _keeper;

        emit KeeperChanged(keeper);
    }

    function setMinter(address newMinter) virtual public onlyOwner {
        // can zero
        _minter = IMerlinMinter(newMinter);
        if (newMinter != address(0)) {
            require(newMinter == MERLIN.getOwner(), 'VaultController: not merlin minter');
            _stakingToken.safeApprove(newMinter, 0);
            _stakingToken.safeApprove(newMinter, uint(- 1));
        }
    }

    function setMerlinChef(IMerlinChef newMerlinChef) virtual public onlyOwner {
        require(address(_merlinChef) == address(0), 'VaultController: setMerlinChef only once');
        _merlinChef = newMerlinChef;
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(_stakingToken), 'VaultController: cannot recover underlying token');
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}