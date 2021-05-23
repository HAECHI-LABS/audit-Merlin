// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../interface/IMerlinMinter.sol";

interface IStrategyHelper {
    function tokenPriceInBNB(address _token) view external returns(uint);
    function cakePriceInBNB() view external returns(uint);
    function bnbPriceInUSD() view external returns(uint);
    function profitOf(IMerlinMinter minter, address _flip, uint amount) external view returns (uint _usd, uint _merlin, uint _bnb);

    function tvl(address _flip, uint amount) external view returns (uint);    // in USD
    function tvlInBNB(address _flip, uint amount) external view returns (uint);    // in BNB
    function apy(IMerlinMinter minter, uint pid) external view returns(uint _usd, uint _merlin, uint _bnb);
}
