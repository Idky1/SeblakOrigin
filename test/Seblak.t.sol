// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {SeblakOrigin} from "../src/SeblakOrigin.sol";
import {SeblakAgents, ISeblakMine, IIdentityRegistry} from "../src/SeblakAgents.sol";
import {SeblakMine} from "../src/SeblakMine.sol";
import {SeblakMarket} from "../src/SeblakMarket.sol";

contract MockRegistry {
    mapping(address => uint256) public balanceOf;
    function give(address a) external { balanceOf[a] = 1; }
}

contract SeblakTest is Test {
    MockRegistry reg;
    SeblakOrigin tok;
    SeblakAgents ag;
    SeblakMine mine;
    SeblakMarket mkt;
    address dev = address(0xD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant PRICE = 1000e18;

    function setUp() public {
        vm.startPrank(dev, dev);
        tok = new SeblakOrigin(1_000_000_000e18, dev);
        reg = new MockRegistry();
        reg.give(alice);
        reg.give(bob);
        ag = new SeblakAgents(tok, IIdentityRegistry(address(reg)), PRICE, 10_000, 10, dev);
        mine = new SeblakMine(tok, address(ag), 200);
        ag.setMine(ISeblakMine(address(mine)));
        mkt = new SeblakMarket(tok, ag, address(mine));
        ag.setMintEnabled(true);
        tok.transfer(address(mine), 30_000_000e18);
        tok.transfer(alice, 20_000e18);
        tok.transfer(bob, 20_000e18);
        vm.stopPrank();
    }

    function _mint(address who) internal returns (uint256 id) {
        vm.startPrank(who, who);
        tok.approve(address(ag), type(uint256).max);
        id = ag.mint("pedas level lima");
        vm.stopPrank();
    }

    function testMintBurns() public {
        uint256 id = _mint(alice);
        assertEq(id, 1);
        assertEq(tok.balanceOf(ag.BURN()), PRICE);
        assertEq(tok.balanceOf(alice), 19_000e18);
        assertGt(mine.weightOf(1), 0);
        assertEq(mine.totalWeight(), mine.weightOf(1));
        string memory uri = ag.tokenURI(1);
        assertGt(bytes(uri).length, 100);
    }

    function testWalletLimit() public {
        for (uint256 i; i < 10; i++) _mint(alice);
        vm.prank(alice, alice);
        vm.expectRevert(SeblakAgents.WalletLimit.selector);
        ag.mint("");
    }

    function testNeedsAgentId() public {
        address carol = address(0xCA401);
        vm.prank(dev);
        tok.transfer(carol, 5000e18);
        vm.startPrank(carol, carol);
        tok.approve(address(ag), type(uint256).max);
        vm.expectRevert(SeblakAgents.NoAgentId.selector);
        ag.mint("");
        vm.stopPrank();
        reg.give(carol);
        vm.prank(carol, carol);
        ag.mint("");
        assertEq(ag.balanceOf(carol), 1);
    }

    function testNoContractMint() public {
        vm.prank(alice, bob);
        vm.expectRevert(SeblakAgents.NoContracts.selector);
        ag.mint("");
    }

    function testBadDirective() public {
        vm.startPrank(alice, alice);
        tok.approve(address(ag), type(uint256).max);
        vm.expectRevert(SeblakAgents.BadDirective.selector);
        ag.mint('he said "hi"');
        vm.stopPrank();
    }

    function testBacklogAndMining() public {
        vm.warp(block.timestamp + 1 hours); // no miners: backlog stacks
        uint256 id = _mint(alice);
        assertApproxEqRel(mine.backlog() + 0, 600_000e18, 1e15); // 2% of 30M
        vm.warp(block.timestamp + 1 hours);
        uint256 c = mine.claimable(alice);
        assertGt(c, 1_100_000e18); // backlog + another hour
        vm.prank(alice);
        uint256 got = mine.claim();
        assertEq(got, c);
        assertEq(tok.balanceOf(alice), 19_000e18 + got);
        id;
    }

    function testProRata() public {
        _mint(alice);
        _mint(bob);
        uint256 wa = mine.weightOf(1);
        uint256 wb = mine.weightOf(2);
        vm.warp(block.timestamp + 3 hours);
        uint256 ca = mine.claimable(alice);
        uint256 cb = mine.claimable(bob);
        // alice got first-hour-alone share 0; both from same time (same block) so ratio = weights
        assertApproxEqRel(ca * wb, cb * wa, 1e12);
    }

    function testSolvency() public {
        for (uint256 i; i < 5; i++) { _mint(alice); _mint(bob); }
        for (uint256 h; h < 200; h++) {
            vm.warp(block.timestamp + 1 hours);
            if (h % 7 == 0) { vm.prank(alice); mine.claim(); }
        }
        vm.prank(bob); mine.claim();
        vm.prank(alice); mine.claim();
        assertGe(tok.balanceOf(address(mine)), mine.reserved());
    }

    function testMarketSettlesAndTaxes() public {
        uint256 id = _mint(alice);
        vm.warp(block.timestamp + 2 hours);
        uint256 owedAlice = mine.pending(id);
        vm.startPrank(alice, alice);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(id, 5000e18);
        vm.stopPrank();
        uint256 poolBefore = tok.balanceOf(address(mine));
        vm.startPrank(bob, bob);
        tok.approve(address(mkt), type(uint256).max);
        mkt.buy(id, 5000e18);
        vm.stopPrank();
        assertEq(ag.ownerOf(id), bob);
        assertEq(mine.credit(alice), owedAlice);
        assertEq(mine.pending(id), 0);
        assertEq(tok.balanceOf(address(mine)) - poolBefore, 300e18); // 150 + 150
        assertEq(tok.balanceOf(bob), 20_000e18 - 5150e18);
        vm.prank(alice);
        assertEq(mine.claim(), owedAlice);
    }

    function testMarketStale() public {
        uint256 id = _mint(alice);
        vm.startPrank(alice, alice);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(id, 5000e18);
        ag.transferFrom(alice, address(0xCAFE), id);
        vm.stopPrank();
        vm.startPrank(bob, bob);
        tok.approve(address(mkt), type(uint256).max);
        vm.expectRevert(SeblakMarket.Stale.selector);
        mkt.buy(id, 5000e18);
        vm.stopPrank();
    }
}
