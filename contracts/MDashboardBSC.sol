// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

import "./interface/IMasterChef.sol";
import "./interface/IPancakePair.sol";
import "./interface/IPancakeFactory.sol";
import "./interfaces/IMStrategy.sol";
import "./interfaces/IMMerlinMinter.sol";
import "./interfaces/IMerlinPool.sol";

import "./library/SafeDecimal.sol";
import "./MPriceCalculatorBSC.sol";

/**
 * @dev Implementation of the {MDashboardBSC}.
 */
contract MDashboardBSC is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    struct VaultInfo {
        address PriceCalculator;
        address WBNB;
        address MERL;
        address CAKE;
        address BTCB;
        address ETH;
        address VaultCakeToCake;
        address MerlinPool;
        address PancakeChef;
        address PancakeFactory;
    }

    VaultInfo public vaultInfo;

    struct PoolInfoBSC {
        address pool;
        uint balance;
        uint principal;
        uint available;
        uint tvl;
        uint utilized;
        uint liquidity;
        uint pBASE;
        uint pMERL;
        uint pInBNB;
        uint pInBTC;
        uint pInETH;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
        uint portfolioInUSD;
    }

    enum PoolTypes {
        MerlinStake, // no perf fee           // MerlinStake => MerlinPool
        MerlinFlip_deprecated, // deprecated
        CakeStake, FlipToFlip, FlipToCake,    // CakeStake => CakeToCake
        Merlin, // no perf fee                // Merlin => VaultMerlin
        MerlinBNB,                            // MerlinBNB => VaultMerlinBNB
        Venus
    }

    MPriceCalculatorBSC public priceCalculator;

    uint private constant BLOCK_PER_YEAR = 10512000;
    uint private constant BLOCK_PER_DAY = 28800;

    address public WBNB;
    address public MERL;
    address public CAKE;
    address public BTCB;
    address public ETH;
    address public VaultCakeToCake;

    IMerlinPool private merlinPool;
    IMasterChef private pancakeChef;
    IPancakeFactory private factory;

    /* ========== STATE VARIABLES ========== */

    mapping(address => PoolTypes) public poolTypes;
    mapping(address => uint) public pancakePoolIds;
    mapping(address => bool) public perfExemptions;

    IMStrategy private vaultMerlin;

    /**
     * @dev Initializes the contract with given `vaultInfo_`.
     */
    constructor(VaultInfo memory vaultInfo_) public {
        priceCalculator = MPriceCalculatorBSC(vaultInfo_.PriceCalculator);
        WBNB = vaultInfo_.WBNB;
        MERL = vaultInfo_.MERL;
        CAKE = vaultInfo_.CAKE;
        BTCB = vaultInfo_.BTCB;
        ETH = vaultInfo_.ETH;
        VaultCakeToCake = vaultInfo_.VaultCakeToCake;
        merlinPool = IMerlinPool(vaultInfo_.MerlinPool);
        pancakeChef = IMasterChef(vaultInfo_.PancakeChef);
        factory = IPancakeFactory(vaultInfo_.PancakeFactory);

        vaultInfo = vaultInfo_;

        __Ownable_init();
    }

    /* ========== INITIALIZER ========== */

    /*
    function initialize() external initializer {
        __Ownable_init();
    }
    */

    /* ========== Restricted Operation ========== */

    function setPoolType(address pool, PoolTypes poolType) public onlyOwner {
        poolTypes[pool] = poolType;
    }

    function setPancakePoolId(address pool, uint pid) public onlyOwner {
        pancakePoolIds[pool] = pid;
    }

    function setPerfExemption(address pool, bool exemption) public onlyOwner {
        perfExemptions[pool] = exemption;
    }

    function setVaultMerlin(address vaultMerlin_) public onlyOwner {
        vaultMerlin = IMStrategy(vaultMerlin_);
    }

    /* ========== View Functions ========== */

    function poolTypeOf(address pool) public view returns (PoolTypes) {
        return poolTypes[pool];
    }

    /* ========== Profit Calculation ========== */

    function calculateProfit(address pool, address account) public view returns (uint profit, uint profitInBNB) {
        PoolTypes poolType = poolTypes[pool];
        profit = 0;
        profitInBNB = 0;

        if (poolType == PoolTypes.MerlinStake) {
            // profit as bnb
            (profit,) = priceCalculator.valueOfAsset(address(merlinPool.rewardsToken()), merlinPool.earned(account));
            profitInBNB = profit;
        }
        else if (poolType == PoolTypes.Merlin) {
            // profit as bnb
            (profit,) = priceCalculator.valueOfAsset(address(vaultMerlin.rewardsToken()), vaultMerlin.earned(account));
            profitInBNB = profit;
        }
        else if (poolType == PoolTypes.CakeStake || poolType == PoolTypes.FlipToFlip || poolType == PoolTypes.Venus) {
            // profit as underlying
            IMStrategy strategy = IMStrategy(pool);
            profit = strategy.earned(account);
            (profitInBNB,) = priceCalculator.valueOfAsset(strategy.stakingToken(), profit);
        }
        else if (poolType == PoolTypes.FlipToCake || poolType == PoolTypes.MerlinBNB) {
            // profit as cake
            IMStrategy strategy = IMStrategy(pool);
            profit = strategy.earned(account).mul(IMStrategy(strategy.rewardsToken()).priceShare()).div(1e18);
            (profitInBNB,) = priceCalculator.valueOfAsset(CAKE, profit);
        }
    }

    function profitOfPool(address pool, address account) public view returns (uint profit, uint merlin, uint pInBNB) {
        (uint profitCalculated, uint profitInBNB) = calculateProfit(pool, account);
        profit = profitCalculated;
        merlin = 0;
        pInBNB = profitInBNB;

        if (!perfExemptions[pool]) {
            IMStrategy strategy = IMStrategy(pool);
            if (strategy.minter() != address(0)) {
                profit = profit.mul(70).div(100);
                merlin = IMMerlinMinter(strategy.minter()).amountMerlinToMint(profitInBNB.mul(30).div(100));
            }
        }
    }

    /* ========== TVL Calculation ========== */

    function tvlOfPool(address pool) public view returns (uint tvl) {
        if (poolTypes[pool] == PoolTypes.MerlinStake) {
            (, tvl) = priceCalculator.valueOfAsset(address(merlinPool.stakingToken()), merlinPool.balance());
        }
        else if (poolTypes[pool] == PoolTypes.Merlin) {
            (, tvl) = priceCalculator.valueOfAsset(address(vaultMerlin.stakingToken()), vaultMerlin.balance());
        }
        else {
            IMStrategy strategy = IMStrategy(pool);
            (, tvl) = priceCalculator.valueOfAsset(strategy.stakingToken(), strategy.balance());

            if (strategy.rewardsToken() == VaultCakeToCake) {
                IMStrategy rewardsToken = IMStrategy(strategy.rewardsToken());
                uint rewardsInCake = rewardsToken.balanceOf(pool).mul(rewardsToken.priceShare()).div(1e18);
                (, uint rewardsInUSD) = priceCalculator.valueOfAsset(address(CAKE), rewardsInCake);
                tvl = tvl.add(rewardsInUSD);
            }
        }
    }

    /* ========== Pool Information ========== */

    function infoOfPool(address pool, address account) public view returns (PoolInfoBSC memory) {
        PoolInfoBSC memory poolInfo;

        IMStrategy strategy = IMStrategy(pool);
        (uint pBASE, uint pMERL, uint pInBNB) = profitOfPool(pool, account);

        poolInfo.pool = pool;
        poolInfo.balance = strategy.balanceOf(account);
        poolInfo.principal = strategy.principalOf(account);
        poolInfo.available = strategy.withdrawableBalanceOf(account);
        poolInfo.tvl = tvlOfPool(pool);
        poolInfo.utilized = 0;
        poolInfo.liquidity = 0;
        poolInfo.pBASE = pBASE;
        poolInfo.pMERL = pMERL;
        poolInfo.pInBNB = pInBNB;
        poolInfo.pInBTC = (priceCalculator.priceOfBNB().mul(1e18)).div(priceCalculator.priceOfBTC()).mul(pInBNB).div(1e18);
        poolInfo.pInETH = (priceCalculator.priceOfBNB().mul(1e18)).div(priceCalculator.priceOfETH()).mul(pInBNB).div(1e18);
        poolInfo.portfolioInUSD = portfolioOfPoolInUSD(pool, account);

        PoolTypes poolType = poolTypeOf(pool);
        if (poolType != PoolTypes.MerlinStake && strategy.minter() != address(0)) {
            IMMerlinMinter minter = IMMerlinMinter(strategy.minter());
            poolInfo.depositedAt = strategy.depositedAt(account);
            poolInfo.feeDuration = minter.WITHDRAWAL_FEE_FREE_PERIOD();
            poolInfo.feePercentage = minter.WITHDRAWAL_FEE();
        }
        return poolInfo;
    }

    function poolsOf(address account, address[] memory pools) public view returns (PoolInfoBSC[] memory) {
        PoolInfoBSC[] memory results = new PoolInfoBSC[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            results[i] = infoOfPool(pools[i], account);
        }
        return results;
    }

    /* ========== Portfolio Calculation ========== */

    function stakingTokenValueInUSD(address pool, address account) internal view returns (uint tokenInUSD) {
        PoolTypes poolType = poolTypes[pool];

        address stakingToken;
        if (poolType == PoolTypes.MerlinStake) {
            stakingToken = MERL;
        } else {
            stakingToken = IMStrategy(pool).stakingToken();
        }

        if (stakingToken == address(0)) return 0;
        (, tokenInUSD) = priceCalculator.valueOfAsset(stakingToken, IMStrategy(pool).principalOf(account));
    }

    function portfolioOfPoolInUSD(address pool, address account) internal view returns (uint) {
        uint tokenInUSD = stakingTokenValueInUSD(pool, account);
        (, uint profitInBNB) = calculateProfit(pool, account);
        uint profitInMERL = 0;

        if (!perfExemptions[pool]) {
            IMStrategy strategy = IMStrategy(pool);
            if (strategy.minter() != address(0)) {
                profitInBNB = profitInBNB.mul(70).div(100);
                profitInMERL = IMMerlinMinter(strategy.minter()).amountMerlinToMint(profitInBNB.mul(30).div(100));
            }
        }

        (, uint profitBNBInUSD) = priceCalculator.valueOfAsset(WBNB, profitInBNB);
        (, uint profitMERLInUSD) = priceCalculator.valueOfAsset(MERL, profitInMERL);
        return tokenInUSD.add(profitBNBInUSD).add(profitMERLInUSD);
    }

    function portfolioOf(address account, address[] memory pools) public view returns (uint deposits) {
        deposits = 0;
        for (uint i = 0; i < pools.length; i++) {
            deposits = deposits.add(portfolioOfPoolInUSD(pools[i], account));
        }
    }

    /* ========== APY Calculation ========== */

    function cakeCompound(uint pid, uint compound) private view returns (uint) {
        if (pid >= pancakeChef.poolLength()) return 0;

        (address token, uint allocPoint,,) = pancakeChef.poolInfo(pid);
        (uint valueInBNB,) = priceCalculator.valueOfAsset(token, IBEP20(token).balanceOf(address(pancakeChef)));
        if (valueInBNB == 0) return 0;

        (uint cakePriceInBNB,) = priceCalculator.valueOfAsset(address(CAKE), 1e18);
        uint cakePerYearOfPool = pancakeChef.cakePerBlock().mul(BLOCK_PER_YEAR).mul(allocPoint).div(pancakeChef.totalAllocPoint());
        uint apr = cakePriceInBNB.mul(cakePerYearOfPool).div(valueInBNB);
        return apr.div(compound).add(1e18).power(compound).sub(1e18);
    }


    function compoundingAPY(uint pid, uint compound, PoolTypes poolType) private view returns (uint) {
        if (poolType == PoolTypes.MerlinStake) {
            (uint merlPriceInBNB,) = priceCalculator.valueOfAsset(address(MERL), 1e18);
            (uint rewardsPriceInBNB,) = priceCalculator.valueOfAsset(address(merlinPool.rewardsToken()), 1e18);

            uint poolSize = merlinPool.totalSupply();
            if (poolSize == 0) {
                poolSize = 1e18;
            }

            uint rewardsOfYear = merlinPool.rewardRate().mul(1e18).div(poolSize).mul(365 days);
            return rewardsOfYear.mul(rewardsPriceInBNB).div(merlPriceInBNB);
        }
        else if (poolType == PoolTypes.Merlin) {
            (uint merlPriceInBNB,) = priceCalculator.valueOfAsset(address(MERL), 1e18);
            (uint rewardsPriceInBNB,) = priceCalculator.valueOfAsset(address(vaultMerlin.rewardsToken()), 1e18);

            uint poolSize = vaultMerlin.totalSupply();
            if (poolSize == 0) {
                poolSize = 1e18;
            }

            uint rewardsOfYear = vaultMerlin.rewardRate().mul(1e18).div(poolSize).mul(365 days);
            return rewardsOfYear.mul(rewardsPriceInBNB).div(merlPriceInBNB);
        }
        /*
        else if (poolType == PoolTypes.MerlinFlip) {
            (uint flipPriceInBNB,) = priceCalculator.valueOfAsset(address(bunnyBnbPool.token()), 1e18);
            (uint merlPriceInBNB,) = priceCalculator.valueOfAsset(address(BUNNY), 1e18);

            IBunnyMinter minter = IBunnyMinter(address(bunnyBnbPool.minter()));
            uint mintPerYear = minter.amountBunnyToMintForBunnyBNB(1e18, 365 days);
            return mintPerYear.mul(merlPriceInBNB).div(flipPriceInBNB);
        }
        */
        else if (poolType == PoolTypes.CakeStake || poolType == PoolTypes.FlipToFlip) {
            return cakeCompound(pid, compound);
        }
        else if (poolType == PoolTypes.FlipToCake || poolType == PoolTypes.MerlinBNB) {
            // https://en.wikipedia.org/wiki/Geometric_series
            uint dailyApyOfPool = cakeCompound(pid, 1).div(compound);
            uint dailyApyOfCake = cakeCompound(0, 1).div(compound);
            uint cakeAPY = cakeCompound(0, 365);
            return dailyApyOfPool.mul(cakeAPY).div(dailyApyOfCake);
        }
        return 0;
    }

    function apyOfPool(address pool, uint compound) public view returns (uint apyPool, uint apyMerlin) {
        PoolTypes poolType = poolTypes[pool];
        uint _apy = compoundingAPY(pancakePoolIds[pool], compound, poolType);
        apyPool = _apy;
        apyMerlin = 0;

        IMStrategy strategy = IMStrategy(pool);
        if (strategy.minter() != address(0)) {
            uint compounding = _apy.mul(70).div(100);
            uint inflation = priceCalculator.priceOfMerlin().mul(1e18).div(priceCalculator.priceOfBNB().mul(1e18).div(IMMerlinMinter(strategy.minter()).merlinPerProfitBNB()));
            uint merlinIncentive = _apy.mul(30).div(100).mul(inflation).div(1e18);

            apyPool = compounding;
            apyMerlin = merlinIncentive;
        }
    }
}
