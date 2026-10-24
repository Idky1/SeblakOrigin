// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IEthVault {
    function deposit() external payable;
    function claimFor(uint256 id) external returns (uint256);
}

/// @title SeblakMarketEth - fixed-price Seblak Agents market in ETH.
/// 5% of every sale (taken from the seller's proceeds) goes to SeblakEthVault and is shared among all agents.
/// No owner and no admin fee.
contract SeblakMarketEth is ReentrancyGuard {
    uint256 public constant FEE_BPS = 500;

    IERC721 public immutable agents;
    IEthVault public immutable vault;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public volume;
    uint256 public trades;
    uint256 public feesToVault;

    event Listed(uint256 indexed id, address indexed seller, uint256 price);
    event Cancelled(uint256 indexed id);
    event Bought(uint256 indexed id, address indexed seller, address indexed buyer, uint256 price, uint256 fee);

    error NotOwner();
    error NotListed();
    error NotApproved();
    error BadPrice();
    error PayFailed();

    constructor(IERC721 agents_, IEthVault vault_) {
        agents = agents_;
        vault = vault_;
    }

    function list(uint256 id, uint256 price) external {
        if (price == 0) revert BadPrice();
        if (agents.ownerOf(id) != msg.sender) revert NotOwner();
        if (!agents.isApprovedForAll(msg.sender, address(this)) && agents.getApproved(id) != address(this)) {
            revert NotApproved();
        }
        listings[id] = Listing(msg.sender, price);
        emit Listed(id, msg.sender, price);
    }

    function cancel(uint256 id) external {
        if (listings[id].seller != msg.sender) revert NotOwner();
        delete listings[id];
        emit Cancelled(id);
    }

    /// @notice Pay exactly the listed price in ETH.
    function buy(uint256 id) external payable nonReentrant {
        Listing memory l = listings[id];
        if (l.seller == address(0)) revert NotListed();
        if (msg.value != l.price) revert BadPrice();
        delete listings[id];
        // stale listing: the agent moved since it was listed
        if (agents.ownerOf(id) != l.seller) revert NotListed();

        // ETH the agent earned so far goes to the seller, not the buyer
        try vault.claimFor(id) {} catch {}

        uint256 fee = (l.price * FEE_BPS) / 10_000;
        agents.safeTransferFrom(l.seller, msg.sender, id);
        vault.deposit{value: fee}();
        (bool ok,) = l.seller.call{value: l.price - fee}("");
        if (!ok) revert PayFailed();

        volume += l.price;
        trades++;
        feesToVault += fee;
        emit Bought(id, l.seller, msg.sender, l.price, fee);
    }
}
