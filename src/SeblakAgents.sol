// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

interface IIdentityRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

interface ISeblakMine {
    function onMint(uint256 id, uint256 weight) external;
    function onTransfer(uint256 id, address from) external;
}

/// @title Seblak Agents - burn $SBLor to mint a miner NFT. Tier (1x / 3x / 9x hashpower) is rolled at mint.
contract SeblakAgents is ERC721Enumerable, Ownable {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    address public constant BURN = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;
    /// @notice ERC-8004 identity registry; only wallets holding an Agent ID may mint
    IIdentityRegistry public immutable identityRegistry;
    uint256 public immutable maxSupply;
    uint256 public immutable maxPerWallet;

    ISeblakMine public mine;
    uint256 public mintPrice;
    bool public mintEnabled;
    uint256 public totalBurned;

    mapping(address => uint256) public mintedBy;
    mapping(uint256 => uint8) public tierOf; // 1, 2, 3
    mapping(uint256 => string) public directiveOf;
    mapping(uint256 => uint256) public mintedAt;

    event Minted(uint256 indexed id, address indexed minter, uint8 tier, uint256 burned, string directive);

    error MintClosed();
    error SoldOut();
    error WalletLimit();
    error BadDirective();
    error NoContracts();
    error MineAlreadySet();
    error NoAgentId();

    constructor(IERC20 token_, IIdentityRegistry identityRegistry_, uint256 mintPrice_, uint256 maxSupply_, uint256 maxPerWallet_, address owner_)
        ERC721("Seblak Agents", "SBLA")
        Ownable(owner_)
    {
        token = token_;
        identityRegistry = identityRegistry_;
        mintPrice = mintPrice_;
        maxSupply = maxSupply_;
        maxPerWallet = maxPerWallet_;
    }

    // ---------------------------------------------------------------- admin

    function setMine(ISeblakMine mine_) external onlyOwner {
        if (address(mine) != address(0)) revert MineAlreadySet();
        mine = mine_;
    }

    function setMintEnabled(bool on) external onlyOwner {
        require(address(mine) != address(0), "mine not set");
        mintEnabled = on;
    }

    function setMintPrice(uint256 p) external onlyOwner {
        mintPrice = p;
    }

    // ---------------------------------------------------------------- mint

    /// @param directive optional motto for the agent, max 120 printable ASCII chars, no " \ < > &
    function mint(string calldata directive) external returns (uint256 id) {
        if (!mintEnabled) revert MintClosed();
        if (msg.sender != tx.origin) revert NoContracts(); // stops revert-and-reroll from contracts
        if (!hasAgentId(msg.sender)) revert NoAgentId();
        if (totalSupply() >= maxSupply) revert SoldOut();
        if (mintedBy[msg.sender] >= maxPerWallet) revert WalletLimit();
        _checkDirective(directive);

        uint256 price = mintPrice;
        token.safeTransferFrom(msg.sender, BURN, price);
        totalBurned += price;

        id = totalSupply() + 1;
        unchecked {
            mintedBy[msg.sender]++;
        }
        uint8 tier = _roll(id);
        tierOf[id] = tier;
        directiveOf[id] = directive;
        mintedAt[id] = block.number;

        _mint(msg.sender, id);
        mine.onMint(id, weightOfTier(tier));
        emit Minted(id, msg.sender, tier, price, directive);
    }

    function hasAgentId(address who) public view returns (bool) {
        return identityRegistry.balanceOf(who) > 0;
    }

    function _roll(uint256 id) internal view returns (uint8) {
        uint256 r = uint256(
            keccak256(abi.encodePacked(block.prevrandao, blockhash(block.number - 1), block.timestamp, msg.sender, id))
        ) % 100;
        if (r < 4) return 3; // 4%  -> 9x
        if (r < 20) return 2; // 16% -> 3x
        return 1; // 80% -> 1x
    }

    function weightOfTier(uint8 tier) public pure returns (uint256) {
        return tier == 3 ? 9 : tier == 2 ? 3 : 1;
    }

    function _checkDirective(string calldata d) internal pure {
        bytes calldata b = bytes(d);
        if (b.length > 120) revert BadDirective();
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c < 0x20 || c > 0x7e || c == '"' || c == "\\" || c == "<" || c == ">" || c == "&") {
                revert BadDirective();
            }
        }
    }

    // ---------------------------------------------------------------- mining hook

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        if (from != address(0) && from != to) {
            mine.onTransfer(tokenId, from);
        }
        return super._update(to, tokenId, auth);
    }

    // ---------------------------------------------------------------- metadata

    function tierName(uint8 tier) public pure returns (string memory) {
        return tier == 3 ? "Sultan" : tier == 2 ? "Level Pedas" : "Kerupuk";
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        uint8 t = tierOf[id];
        string memory color = t == 3 ? "#ffcc33" : t == 2 ? "#ff5a1f" : "#e8e1d9";
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"><rect width="400" height="400" fill="#140c08"/>',
            '<circle cx="200" cy="170" r="', (60 + 25 * uint256(t)).toString(), '" fill="none" stroke="', color,
            '" stroke-width="6"/><text x="200" y="185" font-family="monospace" font-size="40" fill="', color,
            '" text-anchor="middle">#', id.toString(), '</text>',
            '<text x="200" y="300" font-family="monospace" font-size="22" fill="', color, '" text-anchor="middle">',
            tierName(t), ' ', weightOfTier(t).toString(), 'x</text>',
            '<text x="200" y="350" font-family="monospace" font-size="14" fill="#9a8f86" text-anchor="middle">Seblak Origin Miner</text></svg>'
        );
        string memory json = string.concat(
            '{"name":"Seblak Agent #', id.toString(), '","description":"', directiveOf[id],
            '","attributes":[{"trait_type":"Tier","value":"', tierName(t), '"},{"trait_type":"Hashpower","value":',
            weightOfTier(t).toString(), '}],"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}
