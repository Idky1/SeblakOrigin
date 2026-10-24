// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SeblakEthVault, IAgentsRead, IMineRead} from "../src/SeblakEthVault.sol";
import {SeblakMarketEth, IEthVault} from "../src/SeblakMarketEth.sol";
contract EthVaultForkTest is Test {
    function testForkDeploy() public {
        vm.createSelectFork("https://rpc.mainnet.chain.robinhood.com/");
        address ag = 0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9;
        address mine = 0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52;
        uint256 g = gasleft();
        SeblakEthVault v = new SeblakEthVault(IAgentsRead(ag), IMineRead(mine));
        SeblakMarketEth m = new SeblakMarketEth(IERC721(ag), IEthVault(address(v)));
        console.log("deploy gas", g - gasleft());
        console.log("tx.gasprice", tx.gasprice, "basefee", block.basefee);
        vm.deal(address(this), 1 ether);
        v.deposit{value: 0.01 ether}();
        assertEq(v.backlog(), 0.01 ether); // no agents minted yet
        assertEq(address(m.vault()), address(v));
    }
}
