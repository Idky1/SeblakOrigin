// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAgentsRead {
    function ownerOf(uint256 id) external view returns (address);
    function mintedAt(uint256 id) external view returns (uint256);
}

interface IMineRead {
    function totalWeight() external view returns (uint256);
    function weightOf(uint256 id) external view returns (uint256);
}

/// @title SeblakEthVault - shares every ETH it receives among all Seblak Agents, pro rata to hashpower.
/// Fully on-chain: no owner, no Merkle root, no cycles, nothing expires.
/// Hashpower and mint blocks are read from the existing SeblakMine / SeblakAgents, so no hooks are needed:
/// an agent earns from every deposit made after the block it was minted in.
/// Rewards belong to the agent (like rent): its current owner claims them.
contract SeblakEthVault is ReentrancyGuard {
    uint256 private constant PRECISION = 1e18;

    IAgentsRead public immutable agents;
    IMineRead public immutable mine;

    struct Checkpoint {
        uint64 blk;
        uint192 acc;
    }

    uint256 public accPerWeight; // ETH per hashpower unit, scaled by PRECISION
    uint256 public backlog; // ETH received while no agent existed yet
    uint256 public totalDeposited;
    uint256 public totalClaimed;
    Checkpoint[] public checkpoints; // accPerWeight after the last deposit of each block

    mapping(uint256 => uint256) public paidOf; // settled amount, scaled (weight * acc)
    mapping(uint256 => bool) public touched;

    event Deposited(address indexed from, uint256 amount, uint256 totalWeight);
    event Claimed(uint256 indexed id, address indexed owner, uint256 amount);

    error NotOwner(uint256 id);
    error PayFailed();

    constructor(IAgentsRead agents_, IMineRead mine_) {
        agents = agents_;
        mine = mine_;
    }

    receive() external payable {
        _deposit();
    }

    function deposit() external payable {
        _deposit();
    }

    function _deposit() internal {
        uint256 tw = mine.totalWeight();
        totalDeposited += msg.value;
        if (tw == 0) {
            backlog += msg.value;
            emit Deposited(msg.sender, msg.value, 0);
            return;
        }
        uint256 amt = msg.value + backlog;
        backlog = 0;
        accPerWeight += (amt * PRECISION) / tw;
        uint256 n = checkpoints.length;
        if (n > 0 && checkpoints[n - 1].blk == block.number) {
            checkpoints[n - 1].acc = uint192(accPerWeight);
        } else {
            checkpoints.push(Checkpoint(uint64(block.number), uint192(accPerWeight)));
        }
        emit Deposited(msg.sender, amt, tw);
    }

    /// @notice accPerWeight as it stood at the end of block `blk`.
    function accAt(uint256 blk) public view returns (uint256) {
        uint256 lo;
        uint256 hi = checkpoints.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (checkpoints[mid].blk <= blk) lo = mid + 1;
            else hi = mid;
        }
        return lo == 0 ? 0 : checkpoints[lo - 1].acc;
    }

    function _base(uint256 id, uint256 w) internal view returns (uint256) {
        if (touched[id]) return paidOf[id];
        return (w * accAt(agents.mintedAt(id))) / PRECISION;
    }

    function pending(uint256 id) public view returns (uint256) {
        uint256 w = mine.weightOf(id);
        if (w == 0) return 0;
        return (w * accPerWeight) / PRECISION - _base(id, w);
    }

    function pendingMany(uint256[] calldata ids) external view returns (uint256 total) {
        for (uint256 i; i < ids.length; ++i) total += pending(ids[i]);
    }

    /// @notice Claim the ETH of agents you hold.
    function claim(uint256[] calldata ids) external nonReentrant returns (uint256 amt) {
        for (uint256 i; i < ids.length; ++i) {
            if (agents.ownerOf(ids[i]) != msg.sender) revert NotOwner(ids[i]);
            amt += _settle(ids[i], msg.sender);
        }
        _pay(msg.sender, amt);
    }

    /// @notice Pays an agent's ETH to its current owner. Anyone may call (the market does before a sale).
    function claimFor(uint256 id) external nonReentrant returns (uint256 amt) {
        address owner = agents.ownerOf(id);
        amt = _settle(id, owner);
        _pay(owner, amt);
    }

    function _settle(uint256 id, address owner) internal returns (uint256 amt) {
        uint256 w = mine.weightOf(id);
        if (w == 0) return 0;
        uint256 full = (w * accPerWeight) / PRECISION;
        amt = full - _base(id, w);
        paidOf[id] = full;
        touched[id] = true;
        if (amt > 0) emit Claimed(id, owner, amt);
    }

    function _pay(address to, uint256 amt) internal {
        if (amt == 0) return;
        totalClaimed += amt;
        (bool ok,) = to.call{value: amt}("");
        if (!ok) revert PayFailed();
    }
}
