// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAgentsView {
    function ownerOf(uint256 id) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

/// @title SeblakMine - releases a fixed share of its pool per hour to agents, pro rata to hashpower.
/// Nothing is printed: the pool is whatever $SBLor this contract holds that is not yet owed to miners.
/// Anyone can top it up by simply transferring $SBLor to this address.
contract SeblakMine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable token;
    address public immutable agents;
    uint256 public immutable rateBps; // e.g. 200 = 2% of pool per hour

    uint256 public totalWeight;
    uint256 public accPerWeight; // scaled by PRECISION
    uint256 public reserved; // released to miners, not yet claimed
    uint256 public backlog; // released while no miners were online
    uint256 public lastUpdate;
    uint256 public totalReleased;
    uint256 public totalClaimed;

    mapping(uint256 => uint256) public weightOf;
    mapping(uint256 => uint256) public debtOf;
    mapping(address => uint256) public credit; // settled on transfer, claimable by former owner

    event Released(uint256 amount, uint256 totalWeight);
    event Registered(uint256 indexed id, uint256 weight);
    event Settled(uint256 indexed id, address indexed to, uint256 amount);
    event Claimed(address indexed owner, uint256 amount);

    error OnlyAgents();
    error NotOwner(uint256 id);

    constructor(IERC20 token_, address agents_, uint256 rateBps_) {
        require(rateBps_ > 0 && rateBps_ <= 10_000, "rate");
        token = token_;
        agents = agents_;
        rateBps = rateBps_;
        lastUpdate = block.timestamp;
    }

    modifier onlyAgents() {
        if (msg.sender != agents) revert OnlyAgents();
        _;
    }

    // ---------------------------------------------------------------- views

    function pool() public view returns (uint256) {
        uint256 bal = token.balanceOf(address(this));
        return bal > reserved ? bal - reserved : 0;
    }

    function _releasable() internal view returns (uint256 rel) {
        uint256 dt = block.timestamp - lastUpdate;
        if (dt == 0) return 0;
        uint256 p = pool();
        rel = (p * rateBps * dt) / (10_000 * 3600);
        if (rel > p) rel = p;
    }

    function perHour() external view returns (uint256) {
        return (pool() * rateBps) / 10_000;
    }

    function _accNow() internal view returns (uint256 acc) {
        acc = accPerWeight;
        if (totalWeight > 0) {
            acc += ((_releasable() + backlog) * PRECISION) / totalWeight;
        }
    }

    function pending(uint256 id) public view returns (uint256) {
        uint256 w = weightOf[id];
        if (w == 0) return 0;
        return (w * _accNow()) / PRECISION - debtOf[id];
    }

    /// @notice Everything `owner` could claim right now (agents it holds + settled credit).
    function claimable(address owner) external view returns (uint256 total) {
        total = credit[owner];
        IAgentsView a = IAgentsView(agents);
        uint256 n = a.balanceOf(owner);
        for (uint256 i; i < n; ++i) total += pending(a.tokenOfOwnerByIndex(owner, i));
    }

    function hashpowerOf(address owner) external view returns (uint256 total) {
        IAgentsView a = IAgentsView(agents);
        uint256 n = a.balanceOf(owner);
        for (uint256 i; i < n; ++i) total += weightOf[a.tokenOfOwnerByIndex(owner, i)];
    }

    // ---------------------------------------------------------------- accrual

    function update() public {
        uint256 rel = _releasable();
        lastUpdate = block.timestamp;
        if (rel > 0) {
            reserved += rel;
            totalReleased += rel;
        }
        if (totalWeight == 0) {
            backlog += rel; // stacks up for the first miners
        } else {
            uint256 amt = rel + backlog;
            backlog = 0;
            if (amt > 0) {
                accPerWeight += (amt * PRECISION) / totalWeight;
                emit Released(amt, totalWeight);
            }
        }
    }

    function _settle(uint256 id) internal returns (uint256 amt) {
        uint256 w = weightOf[id];
        uint256 full = (w * accPerWeight) / PRECISION;
        amt = full - debtOf[id];
        debtOf[id] = full;
    }

    // ---------------------------------------------------------------- hooks from SeblakAgents

    function onMint(uint256 id, uint256 weight) external onlyAgents {
        update();
        weightOf[id] = weight;
        totalWeight += weight;
        debtOf[id] = (weight * accPerWeight) / PRECISION;
        emit Registered(id, weight);
    }

    /// @dev Called before ownership changes: what the agent mined so far goes to the old owner.
    function onTransfer(uint256 id, address from) external onlyAgents {
        update();
        uint256 amt = _settle(id);
        if (amt > 0) {
            credit[from] += amt;
            emit Settled(id, from, amt);
        }
    }

    // ---------------------------------------------------------------- claim

    /// @notice Claim everything for all agents you hold, plus settled credit.
    function claim() external nonReentrant returns (uint256 amt) {
        update();
        IAgentsView a = IAgentsView(agents);
        uint256 n = a.balanceOf(msg.sender);
        for (uint256 i; i < n; ++i) amt += _settle(a.tokenOfOwnerByIndex(msg.sender, i));
        amt += _takeCredit(msg.sender);
        _pay(msg.sender, amt);
    }

    /// @notice Claim for a chosen set of your agents (useful if you hold very many).
    function claimIds(uint256[] calldata ids) external nonReentrant returns (uint256 amt) {
        update();
        IAgentsView a = IAgentsView(agents);
        for (uint256 i; i < ids.length; ++i) {
            if (a.ownerOf(ids[i]) != msg.sender) revert NotOwner(ids[i]);
            amt += _settle(ids[i]);
        }
        amt += _takeCredit(msg.sender);
        _pay(msg.sender, amt);
    }

    function _takeCredit(address who) internal returns (uint256 c) {
        c = credit[who];
        if (c > 0) credit[who] = 0;
    }

    function _pay(address to, uint256 amt) internal {
        if (amt == 0) return;
        reserved -= amt;
        totalClaimed += amt;
        token.safeTransfer(to, amt);
        emit Claimed(to, amt);
    }
}
