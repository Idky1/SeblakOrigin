// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {SeblakOrigin} from "../src/SeblakOrigin.sol";
import {SeblakAgents, ISeblakMine, IIdentityRegistry} from "../src/SeblakAgents.sol";
import {SeblakMine} from "../src/SeblakMine.sol";
import {SeblakEthVault, IAgentsRead, IMineRead} from "../src/SeblakEthVault.sol";
import {SeblakMarketEth, IEthVault} from "../src/SeblakMarketEth.sol";

contract MockReg {
    mapping(address => uint256) public balanceOf;
    function give(address a) external { balanceOf[a] = 1; }
}

contract EthVaultTest is Test {
    SeblakOrigin tok;
    SeblakAgents ag;
    SeblakMine mine;
    SeblakEthVault vault;
    SeblakMarketEth mkt;
    address dev = address(0xD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    function setUp() public {
        vm.startPrank(dev, dev);
        tok = new SeblakOrigin(1_000_000_000e18, dev);
        MockReg reg = new MockReg();
        reg.give(alice); reg.give(bob); reg.give(carol);
        ag = new SeblakAgents(tok, IIdentityRegistry(address(reg)), 1000e18, 10_000, 10, dev);
        mine = new SeblakMine(tok, address(ag), 200);
        ag.setMine(ISeblakMine(address(mine)));
        ag.setMintEnabled(true);
        tok.transfer(alice, 20_000e18); tok.transfer(bob, 20_000e18); tok.transfer(carol, 20_000e18);
        vm.stopPrank();
        vault = new SeblakEthVault(IAgentsRead(address(ag)), IMineRead(address(mine)));
        mkt = new SeblakMarketEth(ag, IEthVault(address(vault)));
        vm.deal(bob, 10 ether); vm.deal(carol, 10 ether); vm.deal(address(this), 10 ether);
    }

    function _mint(address who) internal returns (uint256 id) {
        vm.startPrank(who, who);
        tok.approve(address(ag), type(uint256).max);
        id = ag.mint("");
        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    function testBacklogGoesToFirstAgents() public {
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vault.backlog(), 1 ether);
        uint256 a = _mint(alice);
        vault.deposit{value: 1 ether}();
        assertApproxEqAbs(vault.pending(a), 2 ether, 1e6);
    }

    function testProRataAndLateMinterGetsNoPast() public {
        uint256 a = _mint(alice);
        vault.deposit{value: 1 ether}();
        uint256 b = _mint(bob);
        assertEq(vault.pending(b), 0);
        vault.deposit{value: 1 ether}();
        uint256 wa = mine.weightOf(a);
        uint256 wb = mine.weightOf(b);
        assertApproxEqAbs(vault.pending(a), 1 ether + (1 ether * wa) / (wa + wb), 1e6);
        assertApproxEqAbs(vault.pending(b), (1 ether * wb) / (wa + wb), 1e6);
        uint256 before = alice.balance;
        uint256[] memory ids = new uint256[](1);
        ids[0] = a;
        vm.prank(alice);
        vault.claim(ids);
        assertApproxEqAbs(alice.balance - before, 1 ether + (1 ether * wa) / (wa + wb), 1e6);
        assertEq(vault.pending(a), 0);
        vm.prank(bob);
        vm.expectRevert();
        vault.claim(ids); // not bob's agent
    }

    function testMarketFeeAndSellerKeepsEarnings() public {
        uint256 a = _mint(alice);
        _mint(carol);
        vault.deposit{value: 1 ether}();
        uint256 earned = vault.pending(a);
        vm.startPrank(alice);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(a, 1 ether);
        vm.stopPrank();
        uint256 before = alice.balance;
        vm.prank(bob);
        mkt.buy{value: 1 ether}(a);
        assertEq(ag.ownerOf(a), bob);
        assertApproxEqAbs(alice.balance - before, 0.95 ether + earned, 1e6);
        assertEq(mkt.feesToVault(), 0.05 ether);
        assertEq(vault.pending(a) > 0, true); // agent a shares its part of the fee, now bob's
        assertEq(address(vault).balance + vault.totalClaimed(), vault.totalDeposited());
    }

    function testWrongPriceAndStaleListing() public {
        uint256 a = _mint(alice);
        vm.startPrank(alice);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(a, 1 ether);
        ag.transferFrom(alice, carol, a);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(SeblakMarketEth.BadPrice.selector);
        mkt.buy{value: 0.5 ether}(a);
        vm.prank(bob);
        vm.expectRevert(SeblakMarketEth.NotListed.selector);
        mkt.buy{value: 1 ether}(a);
    }

    function testFuzzSolvent(uint96 d1, uint96 d2) public {
        _mint(alice); _mint(bob); _mint(carol);
        vault.deposit{value: uint256(d1) % 5 ether}();
        vault.deposit{value: uint256(d2) % 5 ether}();
        uint256 total = vault.pending(1) + vault.pending(2) + vault.pending(3);
        assertLe(total, address(vault).balance);
    }
}
