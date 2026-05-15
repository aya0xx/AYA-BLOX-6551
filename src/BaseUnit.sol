// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC6551Registry} from "erc6551/interfaces/IERC6551Registry.sol";
import {InvalidAddress, InvalidLimit, IncorrectPayment, WithdrawFailed} from "./errors/Errors.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SVGRenderer} from "./lib/SVGRenderer.sol";
import {IBaseUnit} from "./interfaces/IBaseUnit.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// --- Custom Errors ---

/// @notice Transfer recipient is a known TBA — base units cannot be held inside a TBA wallet.
/// @dev Thrown in BaseUnit._update(). Prevents base unit nesting: a base unit held inside
///      its own TBA would be unreachable by any EOA, permanently locking it.
/// @param tokenId   The token ID of the base unit being transferred.
/// @param recipient The TBA address that was the disallowed destination.
error CannotTransferToTBA(uint256 tokenId, address recipient);

/// @notice Total supply cap reached — no further minting is possible.
/// @dev Thrown in BaseUnit.mintBaseUnit() before the counter increment.
///      The supply check occurs before any state changes so no token ID is consumed on revert.
/// @param maxSupply The hard cap that was reached (equals MAX_SUPPLY).
error MaxSupplyReached(uint256 maxSupply);

/// @notice Recipient already holds the maximum allowed number of base units.
/// @dev Thrown in BaseUnit._update(). Enforced on mint and on every secondary-market transfer
///      so the cap cannot be bypassed by peer-to-peer trading.
/// @param wallet The address that has reached the per-wallet cap.
/// @param limit  The maximum units per wallet (equals MAX_UNITS_PER_WALLET).
error WalletLimitReached(address wallet, uint256 limit);

/// @notice Base units are permanent — burn operations are not permitted.
/// @dev Thrown in BaseUnit._update() when `to == address(0)`.
///      Non-burnability is a game-mechanic invariant: completed units must remain visible on-chain.
/// @param tokenId The token ID for which a burn was attempted.
error BaseUnitNonBurnable(uint256 tokenId);

/// @title BaseUnit
/// @author AYA0X.ETH
/// @notice ERC-721 where each token has a Token-Bound Account (ERC-6551). Foundation for the game loop.
/// @dev Hard supply cap and per-wallet holding cap enforced at the ERC-721 state level via _update.
///      ERC721Enumerable enables on-chain globalScore enumeration in SubUnit.
///      REGISTRY is immutable to allow MockRegistry injection in tests.
contract BaseUnit is ERC721Enumerable, ReentrancyGuard, IBaseUnit {
    // --- Immutables ---

    /// @notice ERC-6551 registry used to create Token-Bound Accounts.
    address public immutable REGISTRY;

    /// @notice TBA implementation contract passed to the registry's createAccount.
    address public immutable TBA_IMPLEMENTATION;

    /// @notice Sub unit slot count for type 0 tokens (A UNIT).
    uint256 public immutable TYPE_LIMIT_0;

    /// @notice Sub unit slot count for type 1 tokens (B UNIT).
    uint256 public immutable TYPE_LIMIT_1;

    /// @notice Sub unit slot count for type 2 tokens (C UNIT).
    uint256 public immutable TYPE_LIMIT_2;

    /// @notice Maximum number of base units that can ever be minted.
    uint256 public immutable MAX_SUPPLY;

    /// @notice Maximum base units any single address may hold simultaneously.
    uint256 public immutable MAX_UNITS_PER_WALLET;

    /// @notice Mint price in wei. Exact match enforced — no over/under payment accepted.
    uint256 public immutable BASE_UNIT_PRICE;

    /// @notice Recipient of all ETH collected at mint.
    address public immutable TREASURY;

    // --- State ---

    /// @dev Token ID counter. Incremented before mint so no ID is consumed on a revert. 0-indexed.
    uint256 private _tokenIdCounter;

    /// @dev Maps each base unit token ID to its deterministic TBA address.
    ///      Written once at mint via REGISTRY.account().
    mapping(uint256 => address) private _tbas;

    /// @dev Set of all TBA addresses deployed by this contract.
    ///      Used in _update() to block transfers that would nest a BaseUnit inside its own TBA.
    ///      Written once per token at mint.
    mapping(address => bool) private _isTba;

    // --- Events ---

    /// @notice Emitted when a base unit is minted and its TBA wallet is deployed.
    /// @dev Emitted in mintBaseUnit() after TBA creation and before the ETH transfer to TREASURY.
    ///      `tba` is the deterministic CREATE2 address computed by REGISTRY.account().
    /// @param tokenId  The token ID of the newly minted base unit.
    /// @param owner    The address that received the base unit (msg.sender at mint time).
    /// @param tba      The TBA wallet address deployed for this token.
    /// @param unitType The type assigned to this token (0 = A UNIT, 1 = B UNIT, 2 = C UNIT).
    event BaseUnitMinted(uint256 indexed tokenId, address indexed owner, address tba, uint8 indexed unitType);

    // --- Constructor ---

    /// @notice Deploys BaseUnit with all game-mechanic parameters fixed as immutables.
    /// @param _tbaImplementation  ERC-6551 account implementation for TBA deployment. Must not be zero.
    /// @param _registry           ERC-6551 registry address. Must not be zero. Use canonical address on live networks.
    /// @param _typeLimit0         Sub unit slot count for type 0 tokens (A UNIT). Must be > 0.
    /// @param _typeLimit1         Sub unit slot count for type 1 tokens (B UNIT). Must be > 0.
    /// @param _typeLimit2         Sub unit slot count for type 2 tokens (C UNIT). Must be > 0.
    /// @param _maxSupply          Total base units that can ever be minted. Must be > 0.
    /// @param _maxUnitsPerWallet  Maximum base units any single address may hold. Must be > 0 and <= _maxSupply.
    /// @param _baseUnitPrice      Mint price in wei. Exact-match enforced at mint. 0 = free mint.
    /// @param _treasury           Recipient of all mint proceeds. Must not be zero.
    /// @dev Validates all inputs before assigning immutables. All nine args are immutable post-deploy.
    ///      Reverts with {InvalidAddress} if _tbaImplementation, _registry, or _treasury is address(0).
    ///      Reverts with {InvalidLimit} if any limit or supply is 0, or if _maxUnitsPerWallet > _maxSupply.
    constructor(
        address _tbaImplementation,
        address _registry,
        uint256 _typeLimit0,
        uint256 _typeLimit1,
        uint256 _typeLimit2,
        uint256 _maxSupply,
        uint256 _maxUnitsPerWallet,
        uint256 _baseUnitPrice,
        address _treasury
    ) ERC721("AYA-BLOX-6551", "BLOX") {
        if (_tbaImplementation == address(0)) revert InvalidAddress(_tbaImplementation);
        if (_registry == address(0)) revert InvalidAddress(_registry);
        if (_treasury == address(0)) revert InvalidAddress(_treasury);
        if (_typeLimit0 == 0) revert InvalidLimit(_typeLimit0);
        if (_typeLimit1 == 0) revert InvalidLimit(_typeLimit1);
        if (_typeLimit2 == 0) revert InvalidLimit(_typeLimit2);
        if (_maxSupply == 0) revert InvalidLimit(_maxSupply);
        if (_maxUnitsPerWallet == 0) revert InvalidLimit(_maxUnitsPerWallet);
        if (_maxUnitsPerWallet > _maxSupply) revert InvalidLimit(_maxUnitsPerWallet);
        TBA_IMPLEMENTATION = _tbaImplementation;
        REGISTRY = _registry;
        TYPE_LIMIT_0 = _typeLimit0;
        TYPE_LIMIT_1 = _typeLimit1;
        TYPE_LIMIT_2 = _typeLimit2;
        MAX_SUPPLY = _maxSupply;
        MAX_UNITS_PER_WALLET = _maxUnitsPerWallet;
        BASE_UNIT_PRICE = _baseUnitPrice;
        TREASURY = _treasury;
    }

    // --- External Functions ---

    /// @notice Mints a new base unit NFT and deploys its Token-Bound Account.
    /// @return tokenId The token ID of the newly minted base unit.
    /// @dev Uses Checks-Effects-Interactions: counter incremented and TBA address cached before
    ///      any external calls. nonReentrant is an additional safeguard.
    ///      Reverts with {IncorrectPayment} if msg.value != BASE_UNIT_PRICE.
    ///      Reverts with {MaxSupplyReached} if _tokenIdCounter >= MAX_SUPPLY before this mint.
    ///      Reverts with {WalletLimitReached} if msg.sender balance >= MAX_UNITS_PER_WALLET (via _update).
    ///      Reverts with {WithdrawFailed} if the ETH transfer to TREASURY fails.
    ///      Emits {BaseUnitMinted} on success.
    function mintBaseUnit() external payable nonReentrant returns (uint256 tokenId) {
        // CHECKS
        if (msg.value != BASE_UNIT_PRICE) revert IncorrectPayment(msg.value, BASE_UNIT_PRICE);
        if (_tokenIdCounter >= MAX_SUPPLY) revert MaxSupplyReached(MAX_SUPPLY);

        // EFFECTS
        unchecked {
            tokenId = _tokenIdCounter++;
        }
        address tba =
            IERC6551Registry(REGISTRY).account(TBA_IMPLEMENTATION, bytes32(0), block.chainid, address(this), tokenId);
        _tbas[tokenId] = tba;
        _isTba[tba] = true;

        // INTERACTIONS
        _safeMint(msg.sender, tokenId);
        IERC6551Registry(REGISTRY).createAccount(TBA_IMPLEMENTATION, bytes32(0), block.chainid, address(this), tokenId);
        emit BaseUnitMinted(tokenId, msg.sender, tba, typeOf(tokenId));
        if (msg.value > 0) {
            (bool ok,) = TREASURY.call{value: msg.value}("");
            if (!ok) revert WithdrawFailed();
        }
    }

    /// @notice Returns the number of base units of a specific type held by an address.
    /// @param user      The address to query.
    /// @param unitType  The type to count. Expected values: 0, 1, or 2.
    /// @return count    The number of base units of the given type currently held by user.
    /// @dev O(n) over the user's balance, bounded by MAX_UNITS_PER_WALLET.
    ///      Returns 0 for any address with no base units or a valid but unowned type.
    function typeBalanceOf(address user, uint8 unitType) external view returns (uint256 count) {
        uint256 balance = balanceOf(user);
        for (uint256 i = 0; i < balance;) {
            if (typeOf(tokenOfOwnerByIndex(user, i)) == unitType) count++;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the TBA address for a base unit.
    /// @param tokenId The base unit token ID to query. Returns address(0) if not minted.
    /// @return The deterministic TBA wallet address, or address(0) if the token has not been minted.
    /// @dev The TBA address is computed and cached at mint via REGISTRY.account().
    ///      Callers must treat address(0) as "not minted" — SubUnit.mintSubUnit() reverts on this.
    function getTba(uint256 tokenId) external view returns (address) {
        return _tbas[tokenId];
    }

    /// @notice Returns whether an address is a TBA created by this contract.
    /// @param account The address to query.
    /// @return True if the address is a known TBA for any base unit minted from this contract.
    /// @dev Used in _update() to block transfers that would nest a base unit inside a TBA wallet.
    ///      Returns false for unminted TBA addresses — only set true after mintBaseUnit() completes.
    function isTba(address account) external view returns (bool) {
        return _isTba[account];
    }

    /// @notice Returns the sub unit slot limit for a base unit.
    /// @param tokenId The base unit token ID to query. Minted or unminted — limit is deterministic.
    /// @return The maximum number of sub units for this token's type.
    /// @dev Pure derivation from tokenId % 3: maps to TYPE_LIMIT_0, TYPE_LIMIT_1, or TYPE_LIMIT_2.
    ///      Safe to call for unminted token IDs — does not check ownership or existence.
    function subUnitLimitOf(uint256 tokenId) public view returns (uint256) {
        uint256 t = tokenId % 3;
        if (t == 0) return TYPE_LIMIT_0;
        if (t == 1) return TYPE_LIMIT_1;
        return TYPE_LIMIT_2;
    }

    /// @notice Returns true if this contract implements the given ERC-165 interface
    /// @param interfaceId The ERC-165 interface identifier to check
    /// @return True if the interface is supported, false otherwise
    /// @dev Required by OZ v5 ERC721Enumerable multi-inheritance resolution.
    ///      IERC165 listed explicitly because IBaseUnit → IERC721Enumerable → IERC165 brings a second declaration.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Returns the type (0, 1, or 2) of a base unit.
    /// @param tokenId Any token ID (minted or not — type is determined by tokenId % 3)
    /// @return The unit type: 0, 1, or 2
    function typeOf(uint256 tokenId) public pure returns (uint8) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(tokenId % 3);
    }

    /// @notice Returns a Base64-encoded JSON metadata URI with a fully on-chain SVG image.
    /// @param tokenId The base unit token ID.
    /// @return A data URI in the format: `data:application/json;base64,{base64-encoded JSON}`.
    /// @dev Reverts with the OZ ERC721 nonexistent-token error if tokenId has not been minted.
    ///      All metadata values (type, limit, maxScore) derive from immutables — no per-token storage reads
    ///      beyond the existence check in _requireOwned(). The SVG reflects static slot capacity only.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint8 t = typeOf(tokenId);
        uint256 limit = subUnitLimitOf(tokenId);
        uint256 maxScore = (limit * (limit + 1)) / 2;

        string memory image = Base64.encode(bytes(_buildBaseUnitSvg(tokenId, t, limit, maxScore)));

        string memory json = string.concat(
            '{"name":"AYA-BLOX-6551 #',
            Strings.toString(tokenId),
            '",',
            '"description":"An AYA-BLOX-6551 NFT with a Token-Bound Account (ERC-6551). ',
            "Type ",
            Strings.toString(t),
            " | ",
            Strings.toString(limit),
            ' SubUnit slots.",',
            '"attributes":[',
            '{"trait_type":"Type","value":',
            Strings.toString(t),
            "},",
            '{"trait_type":"Max Slots","value":',
            Strings.toString(limit),
            "},",
            '{"trait_type":"Max Score","value":',
            Strings.toString(maxScore),
            '}],"image":"data:image/svg+xml;base64,',
            image,
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Builds the complete SVG string for a base unit tokenURI — no storage reads.
    ///      All input values are pre-computed by tokenURI() from immutables and tokenId.
    ///      Slot grid reflects full capacity (all empty) — does not read live fill state.
    function _buildBaseUnitSvg(uint256 tokenId, uint8 unitType, uint256 limit, uint256 maxScore)
        private
        pure
        returns (string memory)
    {
        string memory header = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="400" height="400">',
            '<rect width="400" height="400" fill="#0d0d0d"/>',
            '<text x="20" y="44" font-family="monospace" font-size="18" font-weight="bold" fill="#e0e0e0">AYA-BLOX-6551 #',
            Strings.toString(tokenId),
            "</text>",
            '<line x1="20" y1="56" x2="380" y2="56" stroke="#2a2a2a" stroke-width="1"/>'
        );

        string memory stats = string.concat(
            '<text x="20" y="82" font-family="monospace" font-size="12" fill="#555">TYPE</text>',
            '<text x="90" y="82" font-family="monospace" font-size="12" fill="#555">SLOTS</text>',
            '<text x="165" y="82" font-family="monospace" font-size="12" fill="#555">MAX SCORE</text>',
            '<text x="20" y="114" font-family="monospace" font-size="32" font-weight="bold" fill="',
            SVGRenderer.typeColor(unitType),
            '">',
            Strings.toString(unitType),
            "</text>",
            '<text x="90" y="114" font-family="monospace" font-size="18" fill="#e0e0e0">',
            Strings.toString(limit),
            "</text>",
            '<text x="165" y="114" font-family="monospace" font-size="18" fill="#e0e0e0">',
            Strings.toString(maxScore),
            "</text>"
        );

        string memory grid = string.concat(
            '<text x="20" y="140" font-family="monospace" font-size="11" fill="#444">SLOT CAPACITY</text>',
            SVGRenderer.renderSlots(limit, 0)
        );

        string memory footer = string.concat(
            '<text x="20" y="390" font-family="monospace" font-size="10" fill="#2a2a2a">AYA-BLOX-6551 | ERC-6551</text>',
            "</svg>"
        );

        return string.concat(header, stats, grid, footer);
    }

    // --- Internal Overrides ---

    /// @inheritdoc ERC721Enumerable
    /// @dev Enforces four invariants before delegating to ERC721Enumerable._update:
    ///      1. Reverts with {BaseUnitNonBurnable} if to == address(0).
    ///      2. Reverts with {CannotTransferToTBA} if to is a known TBA (from _isTba mapping).
    ///      3. Reverts with {WalletLimitReached} if balanceOf(to) >= MAX_UNITS_PER_WALLET.
    ///      4. Delegates to super._update for ERC721Enumerable ownership bookkeeping.
    ///      Guard order is cheapest-first: zero-address check, mapping lookup, then balance read.
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Enumerable) returns (address) {
        if (to == address(0)) revert BaseUnitNonBurnable(tokenId);
        if (_isTba[to]) revert CannotTransferToTBA(tokenId, to);
        if (balanceOf(to) >= MAX_UNITS_PER_WALLET) {
            revert WalletLimitReached(to, MAX_UNITS_PER_WALLET);
        }
        return super._update(to, tokenId, auth);
    }

    /// @inheritdoc ERC721Enumerable
    function _increaseBalance(address account, uint128 amount) internal override(ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }
}
