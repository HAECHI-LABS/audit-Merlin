// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interface/IPancakePair.sol";
import "./interface/IPancakeFactory.sol";
import "./interface/AggregatorV3Interface.sol";

contract PriceCalculatorBSC is OwnableUpgradeable {
    using SafeMath for uint;

    address public WBNB;
    address public CAKE;
    address public VAI;
    address public BUSD;

    IPancakeFactory private factory;
    AggregatorV3Interface private constant bnbPriceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);

    /* ========== STATE VARIABLES ========== */

    mapping(address => address) private pairTokens;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _wbnb,
        address _cake,
        address _vai,
        address _busd,
        address _factory
    ) external initializer {
        __Ownable_init();

        WBNB = _wbnb;
        CAKE = _cake;
        VAI = _vai;
        BUSD = _busd;

        factory = IPancakeFactory(_factory);

        setPairToken(VAI, BUSD);
    }

    /* ========== Restricted Operation ========== */
    function setPairToken(address asset, address pairToken) public onlyOwner {
        pairTokens[asset] = pairToken;
    }

    /* ========== Value Calculation ========== */

    function priceOfBNB() view public returns (uint) {
        (, int price, , ,) = bnbPriceFeed.latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfCake() view public returns (uint) {
        (, uint cakePriceInUSD) = valueOfAsset(CAKE, 1e18);
        return cakePriceInUSD;
    }

    function pricesInUSD(address[] memory assets) public view returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            (, uint valueInUSD) = valueOfAsset(assets[i], 1e18);
            prices[i] = valueInUSD;
        }
        return prices;
    }

    function valueOfAsset(address asset, uint amount) public view returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            valueInBNB = amount;
            valueInUSD = amount.mul(priceOfBNB()).div(1e18);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IPancakePair(asset).token0() == WBNB || IPancakePair(asset).token1() == WBNB) {
                valueInBNB = amount.mul(IBEP20(WBNB).balanceOf(address(asset))).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else {
                uint balanceToken0 = IBEP20(IPancakePair(asset).token0()).balanceOf(asset);
                (uint token0PriceInBNB,) = valueOfAsset(IPancakePair(asset).token0(), 1e18);

                valueInBNB = amount.mul(balanceToken0).mul(2).mul(token0PriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            }
        }
        else {
            address pairToken = pairTokens[asset] == address(0) ? WBNB : pairTokens[asset];
            address pair = factory.getPair(asset, pairToken);
            valueInBNB = IBEP20(pairToken).balanceOf(pair).mul(amount).div(IBEP20(asset).balanceOf(pair));
            if (pairToken != WBNB) {
                (uint pairValueInBNB,) = valueOfAsset(pairToken, 1e18);
                valueInBNB = valueInBNB.mul(pairValueInBNB).div(1e18);
            }
            valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
        }
    }
}

