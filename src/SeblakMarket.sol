// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMineUpdate {
    function update() external;
}

/// @title SeblakMarket - fixed-price agent market in $SBLor. Buyer pays +3%, seller pays 3%; both go to the Mine.
contract SeblakMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TAX_BPS = 300;

    IERC20 public immutable token;
    IERC721 public immutable agents;
    address public immutable mine;

    struct Listing {
        address seller;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;
    uint256 public volume;
    uint256 public trades;
    uint256 public taxToMine;

    event Listed(uint256 indexed id, address indexed seller, uint256 price);
    event Cancelled(uint256 indexed id);
    event Bought(uint256 indexed id, address indexed seller, address indexed buyer, uint256 price, uint256 tax);

    error NotOwner();
    error NotListed();
    error NotApproved();
    error Stale();

    constructor(IERC20 token_, IERC721 agents_, address mine_) {
        token = token_;
        agents = agents_;
        mine = mine_;
    }

    function list(uint256 id, uint256 price) external {
        if (agents.ownerOf(id) != msg.sender) revert NotOwner();
        if (!agents.isApprovedForAll(msg.sender, address(this)) && agents.getApproved(id) != address(this)) {
            revert NotApproved();
        }
        require(price > 0, "price");
        listings[id] = Listing(msg.sender, price);
        emit Listed(id, msg.sender, price);
    }

    function cancel(uint256 id) external {
        Listing memory l = listings[id];
        if (l.seller == address(0)) revert NotListed();
        if (l.seller != msg.sender && agents.ownerOf(id) != msg.sender) revert NotOwner();
        delete listings[id];
        emit Cancelled(id);
    }

    /// @param maxPrice protects the buyer if the listing is changed before the tx lands
    function buy(uint256 id, uint256 maxPrice) external nonReentrant {
        Listing memory l = listings[id];
        if (l.seller == address(0)) revert NotListed();
        if (l.price > maxPrice) revert Stale();
        if (agents.ownerOf(id) != l.seller) revert Stale();
        delete listings[id];

        uint256 tax = (l.price * TAX_BPS) / 10_000;
        IMineUpdate(mine).update(); // accrue past hours before the tax enlarges the pool
        token.safeTransferFrom(msg.sender, mine, tax * 2); // buyer's 3% + seller's 3%
        token.safeTransferFrom(msg.sender, l.seller, l.price - tax);
        agents.safeTransferFrom(l.seller, msg.sender, id);

        volume += l.price;
        trades += 1;
        taxToMine += tax * 2;
        emit Bought(id, l.seller, msg.sender, l.price, tax * 2);
    }

    function costFor(uint256 id) external view returns (uint256) {
        Listing memory l = listings[id];
        return l.price + (l.price * TAX_BPS) / 10_000;
    }
}
