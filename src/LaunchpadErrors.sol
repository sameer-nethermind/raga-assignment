// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract LaunchpadErrors {
    error ExceedsMaxSupply();
    error ExceedsMaxRaise();
    error IncorrectSupplyCalculation();
    error NotFinalized();
    error NotStarted();
    error AlreadyFinalized();
    error NeitherPausedNorSaleEnded();
    error InvalidAmount();
    error InsufficientUSDCAmount();
    error InsufficientTokenAmount();
    error AmountTooLess();
    error InvalidAddress();
}
