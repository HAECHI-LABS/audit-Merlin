// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;


library PoolConstant {

    enum PoolTypes {
        MerlinPool, MerlinStake, CakeStake, FlipToFlip, FlipToCake, FlipToCakeMaximizer, Merlin
    }

    struct PoolInfoBSC {
        address pool;
        uint balance;
        uint principal;
        uint available;
        uint share;
        uint apyPool;
        uint apyMerlin;
        uint apyBorrow;
        uint tvl;
        uint utilized;
        uint liquidity;
        uint pUSD;
        uint pBNB;
        uint pBASE;
        uint pMERLIN;
        uint pCAKE;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
    }

    struct PoolInfoETH {
        address pool;
        uint collateralETH;
        uint collateralBSC;
        uint bnbDebt;
        uint leverage;
        uint tvl;
        uint updatedAt;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
    }
}
