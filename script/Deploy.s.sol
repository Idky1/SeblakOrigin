// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {SeblakOrigin} from "../src/SeblakOrigin.sol";
import {SeblakAgents, ISeblakMine, IIdentityRegistry} from "../src/SeblakAgents.sol";
import {SeblakMine} from "../src/SeblakMine.sol";
import {SeblakMarket} from "../src/SeblakMarket.sol";

/// Deploys everything, then hands the whole token supply and Agents ownership to OWNER.
contract Deploy is Script {
    function run() external {
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast();
        SeblakOrigin tok = new SeblakOrigin(1_000_000_000e18, owner);
        SeblakAgents ag = new SeblakAgents(tok, IIdentityRegistry(0x8004A169FB4a3325136EB29fA0ceB6D2e539a432), 1_000e18, 10_000, 10, msg.sender);
        SeblakMine mine = new SeblakMine(tok, address(ag), 200);
        ag.setMine(ISeblakMine(address(mine)));
        SeblakMarket mkt = new SeblakMarket(tok, ag, address(mine));
        ag.transferOwnership(owner);
        vm.stopBroadcast();
        console.log("TOKEN", address(tok));
        console.log("AGENTS", address(ag));
        console.log("MINE", address(mine));
        console.log("MARKET", address(mkt));
    }
}
