// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Seblak Origin ($SBLor) - fixed supply, nothing is ever minted after deploy.
contract SeblakOrigin is ERC20 {
    constructor(uint256 supply, address receiver) ERC20("Seblak Origin", "SBLor") {
        _mint(receiver, supply);
    }
}
