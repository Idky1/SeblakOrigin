// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {SeblakOrigin} from "../src/SeblakOrigin.sol";
import {SeblakAgents} from "../src/SeblakAgents.sol";
import {SeblakMine} from "../src/SeblakMine.sol";
import {SeblakMarket} from "../src/SeblakMarket.sol";

/// Mainnet-fork rehearsal of the launch against the REAL deployed contracts. Local only, never broadcast.
/// Run: forge test --match-contract ForkLaunch --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract ForkLaunchTest is Test {
    SeblakOrigin tok = SeblakOrigin(0x3085510A066Fde9F60B5F732814d38D3cAccEAa3);
    SeblakAgents ag = SeblakAgents(0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9);
    SeblakMine mine = SeblakMine(0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52);
    SeblakMarket mkt = SeblakMarket(0xf3A5E8B8e6Cb6d8aA303e4C194A2B998cFd27ACf);
    address owner = 0xD65eBdE9885e4c0578FbD97B88fb3a00595BE4cb;
    address alice = 0xd305607510E0Db2c95807173c7A05BEA53c1ed36; // real ERC-8004 Agent ID holder (EOA)
    address bob = 0x2B5B35AC5A2d5c1224337BA86bf3816AbEe69da3; // real ERC-8004 Agent ID holder (EOA)
    address carol = address(0xCA401); // no Agent ID
    uint256 constant POOL = 30_000_000e18;

    function setUp() public {
        assertEq(block.chainid, 4663);
        assertEq(ag.owner(), owner);
        assertFalse(ag.mintEnabled());
    }

    function _launchCorrectly() internal {
        vm.startPrank(owner, owner);
        mine.update(); // reset lastUpdate while pool == 0 (see LAUNCH.md)
        tok.transfer(address(mine), POOL);
        ag.setMintEnabled(true);
        // seed two test wallets
        tok.transfer(alice, 20_000e18);
        tok.transfer(bob, 20_000e18);
        tok.transfer(carol, 20_000e18);
        vm.stopPrank();
    }

    function _mint(address who, string memory d) internal returns (uint256 id) {
        vm.startPrank(who, who);
        tok.approve(address(ag), 1_000e18);
        id = ag.mint(d);
        vm.stopPrank();
    }

    function testFullFlow() public {
        // before launch: mint closed
        vm.prank(alice, alice);
        vm.expectRevert(SeblakAgents.MintClosed.selector);
        ag.mint("");

        _launchCorrectly();
        assertEq(mine.pool(), POOL);
        assertEq(mine.perHour(), 600_000e18);

        // no approval -> ERC20InsufficientAllowance
        vm.prank(alice, alice);
        vm.expectRevert();
        ag.mint("pedas");

        // no Agent ID
        vm.startPrank(carol, carol);
        tok.approve(address(ag), 1_000e18);
        vm.expectRevert(SeblakAgents.NoAgentId.selector);
        ag.mint("");
        vm.stopPrank();

        uint256 burnBefore = tok.balanceOf(ag.BURN());
        uint256 id1 = _mint(alice, "Level 5, no mercy");
        uint256 id2 = _mint(bob, "kerupuk forever");
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(ag.totalSupply(), 2);
        assertEq(ag.totalBurned(), 2_000e18);
        assertEq(tok.balanceOf(ag.BURN()) - burnBefore, 2_000e18);
        console.log("tier #1", ag.tierOf(1), "tier #2", ag.tierOf(2));
        console.log("hashpower alice", mine.hashpowerOf(alice), "bob", mine.hashpowerOf(bob));

        vm.warp(block.timestamp + 1 hours);
        uint256 ca = mine.claimable(alice);
        uint256 cb = mine.claimable(bob);
        console.log("claimable after 1h alice (SBLor)", ca / 1e18);
        console.log("claimable after 1h bob   (SBLor)", cb / 1e18);
        assertGt(ca, 0);
        assertApproxEqRel(ca + cb, 600_000e18, 1e16); // ~2% of 30M in one hour (+ tiny backlog)

        uint256 balA = tok.balanceOf(alice);
        vm.prank(alice);
        uint256 got = mine.claim();
        assertEq(got, ca);
        assertEq(tok.balanceOf(alice), balA + got);
        assertEq(mine.claimable(alice), 0);
        assertGe(tok.balanceOf(address(mine)), mine.reserved());

        // market: alice lists #1, bob buys with 3%+3% tax to mine
        vm.startPrank(alice, alice);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(id1, 5_000e18);
        vm.stopPrank();
        assertEq(mkt.costFor(id1), 5_150e18);
        uint256 mineBal = tok.balanceOf(address(mine));
        vm.startPrank(bob, bob);
        tok.approve(address(mkt), 5_150e18);
        mkt.buy(id1, 5_000e18);
        vm.stopPrank();
        assertEq(ag.ownerOf(id1), bob);
        assertEq(tok.balanceOf(address(mine)) - mineBal, 300e18);

        // cancel path
        vm.startPrank(bob, bob);
        ag.setApprovalForAll(address(mkt), true);
        mkt.list(id2, 9_000e18);
        mkt.cancel(id2);
        vm.stopPrank();
        (address s,) = mkt.listings(id2);
        assertEq(s, address(0));

        // directive rules
        vm.startPrank(alice, alice);
        tok.approve(address(ag), 1_000e18);
        vm.expectRevert(SeblakAgents.BadDirective.selector);
        ag.mint("bad <tag>");
        vm.stopPrank();
    }

    /// CAVEAT demo: funding the pool by plain transfer WITHOUT calling update() first releases
    /// (hours since deploy) x 2% of the pool at once into the backlog, which the first minter takes.
    function testStaleLastUpdateCaveat() public {
        uint256 hrs = (block.timestamp - mine.lastUpdate()) / 3600;
        console.log("hours since lastUpdate on mainnet:", hrs);
        vm.warp(block.timestamp + 12 hours); // e.g. owner funds tomorrow without update()
        vm.startPrank(owner, owner);
        tok.transfer(address(mine), POOL);
        ag.setMintEnabled(true);
        tok.transfer(alice, 20_000e18);
        vm.stopPrank();
        _mint(alice, "");
        uint256 backlog = mine.backlog();
        console.log("backlog grabbed by first minter (SBLor):", backlog / 1e18);
        assertGt(backlog, POOL / 5); // > 20% of the pool in one shot
    }

    function testCorrectOrderKeepsBacklogSmall() public {
        vm.warp(block.timestamp + 12 hours);
        _launchCorrectly();
        vm.warp(block.timestamp + 60); // first mint one minute after launch
        _mint(alice, "");
        console.log("backlog after correct launch + 60s (SBLor):", mine.backlog() / 1e18);
        assertLt(mine.backlog(), 20_000e18);
    }
}
