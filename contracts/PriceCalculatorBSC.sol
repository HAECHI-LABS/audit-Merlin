// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interface/IPancakePair.sol";
import "./interface/IPancakeFactory.sol";
import "./interface/AggregatorV3Interface.sol";
import "./interface/IPriceCalculator.sol";
import "./library/HomoraMath.sol";

/**
 * @dev Implementation of the {PriceCalculatorBSC}.
 */
contract PriceCalculatorBSC is IPriceCalculator, OwnableUpgradeable {
    using SafeMath for uint;
    using HomoraMath for uint;

    struct CalcInfo {
        address WBNB;
        address CAKE;
        address MERL;
        address VAI;
        address BUSD;
        address BTC;
        address ETH;
        address USDT;
        address MERL_BNB;
        address PancakeFactory;
    }

    CalcInfo public calcInfo;

    address public WBNB;
    address public CAKE;
    address public MERL;
    address public VAI;
    address public BUSD;
    address public BTC;
    address public ETH;
    address public USDT;
    address public MERL_BNB;

    IPancakeFactory private factory;

    /* ========== STATE VARIABLES ========== */

    mapping(address => address) public pairTokens;

    /**
     * @dev
     * BSC Mainnet
     * BNB/USD: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
     * BTC/USD: 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf
     * ETH/USD: 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e
     * CAKE/USD: 0xB6064eD41d4f67e353768aA239cA86f4F73665a1
     * DOT/USD: 0xC333eb0086309a16aa7c8308DfD32c8BBA0a2592
     * XRP/USD: 0x93A67D414896A280bF8FFB3b389fE3686E014fda
     * UNI/USD: 0xb57f259E7C24e56a1dA00F66b55A5640d9f9E7e4
     *
     * BSC Testnet
     * BNB/USD: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
     * BTC/USD: 0x5741306c21795FdCBb9b265Ea0255F499DFe515C
     * ETH/USD: 0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7
     */
    mapping(address => address) public tokenFeeds;

    /**
     * @dev Initializes the contract with given `tokens`.
     */
    constructor(CalcInfo memory calcInfo_) public {
        WBNB = calcInfo_.WBNB;
        CAKE = calcInfo_.CAKE;
        MERL = calcInfo_.MERL;
        VAI = calcInfo_.VAI;
        BUSD = calcInfo_.BUSD;
        BTC = calcInfo_.BTC;
        ETH = calcInfo_.ETH;
        USDT = calcInfo_.USDT;
        MERL_BNB = calcInfo_.MERL_BNB;
        factory = IPancakeFactory(calcInfo_.PancakeFactory);

        calcInfo = calcInfo_;
    }

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
        setPairToken(VAI, BUSD);
    }

    /* ========== Restricted Operation ========== */

    function setPairToken(address asset, address pairToken) public onlyOwner {
        pairTokens[asset] = pairToken;
    }

    function setTokenFeed(address asset, address feed) public onlyOwner {
        tokenFeeds[asset] = feed;
    }

    /* ========== Value Calculation ========== */

    function priceOfBNB() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[WBNB]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfCake() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[CAKE]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfMerlin() view public returns (uint) {
        (, uint merlinPriceInUSD) = valueOfAsset(MERL, 1e18);
        return merlinPriceInUSD;
    }

    function priceOfUSDT() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[USDT]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfBTC() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[BTC]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfETH() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[ETH]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function pricesInUSD(address[] memory assets) public view override returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            (, uint valueInUSD) = valueOfAsset(assets[i], 1e18);
            prices[i] = valueInUSD;
        }
        return prices;
    }

    function valueOfAsset(address asset, uint amount) public view override returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            return _oracleValueOf(WBNB, amount);
        } else if (asset == MERL || asset == MERL_BNB) {
            return _unsafeValueOfAsset(asset, amount);
        } else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            return _getPairPrice(asset, amount);
        } else {
            return _oracleValueOf(asset, amount);
        }
    }

    function _oracleValueOf(address asset, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[asset]).latestRoundData();

        if (keccak256(abi.encodePacked(IBEP20(asset).symbol())) == keccak256("BAND")) {
            valueInBNB = uint(price).mul(1e10).mul(amount).div(1e18);
            valueInUSD = valueInBNB.mul(1e18).div(priceOfUSDT());
        } else {
            valueInUSD = uint(price).mul(1e10).mul(amount).div(1e18);
            valueInBNB = valueInUSD.mul(1e18).div(priceOfBNB());
        }
    }

    function _getPairPrice(address pair, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
       address token0 = IPancakePair(pair).token0();
       address token1 = IPancakePair(pair).token1();
       uint totalSupply = IPancakePair(pair).totalSupply();
       (uint r0, uint r1, ) = IPancakePair(pair).getReserves();

       uint sqrtK = HomoraMath.sqrt(r0.mul(r1)).fdiv(totalSupply);
       (uint px0,) = _oracleValueOf(token0, 1e18);
       (uint px1,) = _oracleValueOf(token1, 1e18);
       uint fairPriceInBNB = sqrtK.mul(2).mul(HomoraMath.sqrt(px0)).div(2**56).mul(HomoraMath.sqrt(px1)).div(2**56);

       valueInBNB = fairPriceInBNB.mul(amount).div(1e18);
       valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
    }

    function _unsafeValueOfAsset(address asset, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            valueInBNB = amount;
            valueInUSD = amount.mul(priceOfBNB()).div(1e18);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IPancakePair(asset).totalSupply() == 0) return (0, 0);

            (uint reserve0, uint reserve1, ) = IPancakePair(asset).getReserves();
            if (IPancakePair(asset).token0() == WBNB) {
                valueInBNB = amount.mul(reserve0).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else if (IPancakePair(asset).token1() == WBNB) {
                valueInBNB = amount.mul(reserve1).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else {
                (uint token0PriceInBNB,) = valueOfAsset(IPancakePair(asset).token0(), 1e18);
                valueInBNB = amount.mul(reserve0).mul(2).mul(token0PriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            }
        }
        else {
            address pairToken = pairTokens[asset] == address(0) ? WBNB : pairTokens[asset];
            address pair = factory.getPair(asset, pairToken);
            if (IBEP20(asset).balanceOf(pair) == 0) return (0, 0);

            (uint reserve0, uint reserve1, ) = IPancakePair(pair).getReserves();
            if (IPancakePair(pair).token0() == pairToken) {
                valueInBNB = reserve0.mul(amount).div(reserve1);
            } else if (IPancakePair(pair).token1() == pairToken) {
                valueInBNB = reserve1.mul(amount).div(reserve0);
            } else {
                return (0, 0);
            }

            if (pairToken != WBNB) {
                (uint pairValueInBNB,) = valueOfAsset(pairToken, 1e18);
                valueInBNB = valueInBNB.mul(pairValueInBNB).div(1e18);
            }
            valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
        }
    }
}