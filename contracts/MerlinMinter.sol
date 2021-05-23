// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "./interface/IPancakePair.sol";
import "./interface/IMerlinMinter.sol";
import "./interface/IStakingRewards.sol";
import "./interface/IZapBSC.sol";

import "./PriceCalculatorBSC.sol";

contract MerlinMinter is IMerlinMinter, OwnableUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint public constant FEE_MAX = 10000;

    /* ========== STATE VARIABLES ========== */

    address public MERLIN;
    address public MERLIN_POOL;
    address public DEPLOYER;
    address public WBNB;
    IZapBSC public zapBSC;
    PriceCalculatorBSC public priceCalculator;
    address public TIMELOCK;

    address public merlinChef;
    mapping(address => bool) private _minters;

    uint public PERFORMANCE_FEE;
    uint public override WITHDRAWAL_FEE_FREE_PERIOD;
    uint public override WITHDRAWAL_FEE;

    uint public override merlinPerProfitBNB;

    /* ========== MODIFIERS ========== */

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "MerlinMiner: caller is not the minter");
        _;
    }

    modifier onlyMerlinChef {
        require(msg.sender == merlinChef, "MerlinMiner: caller not the merlin chef");
        _;
    }

    receive() external payable {}

    /* ========== INITIALIZER ========== */
    function initialize(
        address _merlinAddress,
        address _merlinPoolAddress,       
        address _deployerAddress,
        address _wbnb,
        address _zapBSC,
        address _priceCalculator,
        address _timelock
    ) external initializer {
        __Ownable_init();

        MERLIN = _merlinAddress;
        MERLIN_POOL = _merlinPoolAddress;
        DEPLOYER = _deployerAddress;
        WBNB = _wbnb;
        zapBSC = IZapBSC(_zapBSC);
        priceCalculator = PriceCalculatorBSC(_priceCalculator);
        TIMELOCK = _timelock;

        WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
        WITHDRAWAL_FEE = 50;
        PERFORMANCE_FEE = 2900;

        merlinPerProfitBNB = 30;

        IBEP20(MERLIN).approve(MERLIN_POOL, uint(-1));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferMerlinOwner(address _owner) external onlyOwner {
        Ownable(MERLIN).transferOwnership(_owner);
    }

    function setWithdrawalFee(uint _fee) external onlyOwner {
        require(_fee < 500, "wrong fee");
        // less 5%
        WITHDRAWAL_FEE = _fee;
    }

    function setPerformanceFee(uint _fee) external onlyOwner {
        require(_fee < 5000, "wrong fee");
        PERFORMANCE_FEE = _fee;
    }

    function setWithdrawalFeeFreePeriod(uint _period) external onlyOwner {
        WITHDRAWAL_FEE_FREE_PERIOD = _period;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    function setMerlinPerProfitBNB(uint _ratio) external onlyOwner {
        merlinPerProfitBNB = _ratio;
    }

    function setMerlinChef(address _merlinChef) external onlyOwner {
        require(merlinChef == address(0), "MerlinMinter: setMerlinChef only once");
        merlinChef = _merlinChef;
    }

    /* ========== VIEWS ========== */

    function isMinter(address account) public view override returns (bool) {
        if (IBEP20(MERLIN).getOwner() != address(this)) {
            return false;
        }
        return _minters[account];
    }

    function amountMerlinToMint(uint bnbProfit) public view override returns (uint) {
        return bnbProfit.mul(merlinPerProfitBNB);
    }

    function withdrawalFee(uint amount, uint depositedAt) external view override returns (uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) external view override returns (uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    function mintFor(address asset, uint _withdrawalFee, uint _performanceFee, address to, uint) external payable override onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        _transferAsset(asset, feeSum);

        if (asset == MERLIN) {
            IBEP20(MERLIN).safeTransfer(DEAD, feeSum);
            return;
        }
        (uint valueInBNB,) = priceCalculator.valueOfAsset(WBNB, amountBNB);
        uint contribution = valueInBNB.mul(_performanceFee).div(feeSum);

        uint amountBNB = _zapAssetsToBNB(asset);
        if (amountBNB == 0) return;

        IBEP20(WBNB).safeTransfer(MERLIN_POOL, amountBNB);
        IStakingRewards(MERLIN_POOL).notifyRewardAmount(amountBNB);

        uint mintMerlin = amountMerlinToMint(contribution);
        
        if (mintMerlin == 0) return;
        _mint(mintMerlin, to);
    }

    function mint(uint amount) external override onlyMerlinChef {
        if (amount == 0) return;
        _mint(amount, address(this));
    }

    function safeMerlinTransfer(address _to, uint _amount) external override onlyMerlinChef {
        if (_amount == 0) return;

        uint bal = IBEP20(MERLIN).balanceOf(address(this));
        if (_amount <= bal) {
            IBEP20(MERLIN).safeTransfer(_to, _amount);
        } else {
            IBEP20(MERLIN).safeTransfer(_to, bal);
        }
    }

    // @dev should be called when determining mint in governance. Merlin is transferred to the timelock contract.
    function mintGov(uint amount) external override onlyOwner {
        if (amount == 0) return;
        _mint(amount, TIMELOCK);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _transferAsset(address asset, uint amount) private {
        if (asset == address(0)) {
            // case) transferred BNB
            require(msg.value >= amount);
        } else {
            IBEP20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _zapAssetsToBNB(address asset) private returns (uint) {
        if (asset != address(0)) {
            if (IBEP20(asset).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(asset).safeApprove(address(zapBSC), uint(- 1));
            }
        }

        if (asset == address(0)) {
            zapBSC.zapIn{value : address(this).balance}(WBNB);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IBEP20(asset).allowance(address(this), address(zapBSC)) == 0) {
                IBEP20(asset).safeApprove(address(zapBSC), uint(- 1));
            }
            zapBSC.zapOut(asset, IBEP20(asset).balanceOf(address(this)));

            IPancakePair pair = IPancakePair(asset);
            address token0 = pair.token0();
            address token1 = pair.token1();

            if ( token0 != WBNB ) {
                if (IBEP20(token0).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token0).safeApprove(address(zapBSC), uint(- 1));
                }
                zapBSC.zapInToken(token0, IBEP20(token0).balanceOf(address(this)), WBNB);
            }

            if ( token1 != WBNB ) {
                if (IBEP20(token1).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token1).safeApprove(address(zapBSC), uint(- 1));
                }
                zapBSC.zapInToken(token1, IBEP20(token1).balanceOf(address(this)), WBNB);
            }
        }
        else {
            zapBSC.zapInToken(asset, IBEP20(asset).balanceOf(address(this)), WBNB);
        }

        return IBEP20(WBNB).balanceOf(address(this));
    }

    function _mint(uint amount, address to) private {
        BEP20 tokenMERLIN = BEP20(MERLIN);

        tokenMERLIN.mint(amount);
        if (to != address(this)) {
            tokenMERLIN.transfer(to, amount);
        }

        uint merlinForDev = amount.mul(13).div(100);
        tokenMERLIN.mint(merlinForDev);
        IStakingRewards(MERLIN_POOL).stakeTo(merlinForDev, DEPLOYER);
    }
}
