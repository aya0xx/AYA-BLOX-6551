// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBaseUnit} from "./interfaces/IBaseUnit.sol";
import {InvalidAddress, InvalidLimit, IncorrectPayment, WithdrawFailed} from "./errors/Errors.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SVGRenderer} from "./lib/SVGRenderer.sol";

// --- Custom Errors ---

/// @notice Caller does not own the base unit they are attempting to mint into.
/// @dev Thrown in SubUnit.mintSubUnit(). Ownership verified via BASE_UNIT_CONTRACT.ownerOf().
/// @param caller     The address that submitted the mint transaction.
/// @param baseUnitId The base unit token ID that the caller does not own.
error NotBaseUnitOwner(address caller, uint256 baseUnitId);

/// @notice Base unit token ID has not been minted — its TBA does not exist yet.
/// @dev Thrown in SubUnit.mintSubUnit() when getTba(baseUnitId) returns address(0).
/// @param baseUnitId The token ID that has not been minted.
error BaseUnitNotMinted(uint256 baseUnitId);

/// @notice Base unit has no remaining sub unit slots.
/// @dev Thrown in SubUnit.mintSubUnit() when subUnitCountPerBase[baseUnitId] >= limit.
///      Each base unit type has a fixed slot limit (TYPE_LIMIT_0/1/2) determined at BaseUnit deploy.
/// @param baseUnitId The base unit that has reached its slot limit.
/// @param limit      The maximum number of sub units for this token's type.
error BaseUnitSlotsFull(uint256 baseUnitId, uint256 limit);

/// @notice Sub units are mint-only — transfers and burns are permanently disabled.
/// @dev Thrown in SubUnit._update() for any non-mint state transition, and in SubUnit.approve().
///      Non-transferability is a game-mechanic invariant: sub units are permanently bound to their TBA.
/// @param tokenId The sub unit token ID for which the disallowed operation was attempted.
error SubUnitNonTransferable(uint256 tokenId);

/// @notice Sub unit token does not exist.
/// @dev Thrown in SubUnit.getParentBaseUnit() and SubUnit.tokenURI() for unminted or nonexistent IDs.
///      Guards against silent returns of default mapping values (0) for invalid sub unit IDs.
/// @param subUnitId The sub unit token ID that does not exist.
error SubUnitDoesNotExist(uint256 subUnitId);

/// @notice Approvals are permanently disabled — sub units cannot be approved or transferred.
/// @dev Thrown in SubUnit.setApprovalForAll(). Closes the operator approval pathway alongside _update's mint-only guard.
error ApprovalsDisabled();

/// @notice Requested index exceeds the number of sub units minted into the base unit.
/// @dev Thrown in SubUnit.subUnitOfBaseByIndex(). Valid range is 0 to subUnitCountPerBase[baseUnitId]-1.
/// @param baseUnitId The base unit queried.
/// @param index      The out-of-range index that was requested.
error SubUnitIndexOutOfBounds(uint256 baseUnitId, uint256 index);

/// @title SubUnit
/// @author AYA0X.ETH
/// @notice ERC-721 where each token is permanently bound to one base unit's TBA.
///         Mint-only — no transfers, no burns.
///         Score is position-based: slot N earns N+1 points. Accumulated per base unit.
///         Global score loops over all base units owned by an address via ERC721Enumerable.
/// @dev No callback to BaseUnit. No Ownable. No admin surface.
contract SubUnit is ERC721, ReentrancyGuard {
    // --- Immutables ---

    /// @notice The BaseUnit contract this SubUnit system is bound to.
    address public immutable BASE_UNIT_CONTRACT;

    /// @notice Mint price in wei. Exact match enforced — no over/under payment accepted.
    uint256 public immutable SUB_UNIT_PRICE;

    /// @notice Recipient of all ETH collected at mint.
    address public immutable TREASURY;

    // --- State ---

    /// @dev Token ID counter. Incremented before mint.
    uint256 private _tokenIdCounter;

    /// @dev Maps each sub unit to its parent base unit — use getParentBaseUnit() for safe external access
    mapping(uint256 => uint256) private _parentBaseUnit;

    /// @notice Tracks how many sub units have been minted into each base unit's TBA
    mapping(uint256 => uint256) public subUnitCountPerBase;

    /// @notice Score assigned to each sub unit at mint — position index + 1
    mapping(uint256 => uint256) public subUnitScore;

    /// @dev Accumulated score per base unit — use localScore() for safe external access
    mapping(uint256 => uint256) private _baseUnitScore;

    /// @notice Total number of base units that have reached full completion across all players
    uint256 public totalCompleted;

    /// @dev Index-based enumeration: baseUnitId => position => subUnitId
    ///      Mirrors ERC721Enumerable _ownedTokens pattern for the base→sub relationship.
    ///      Length is always subUnitCountPerBase[baseUnitId].
    mapping(uint256 => mapping(uint256 => uint256)) private _subUnitsByBase;

    // --- Events ---

    /// @notice Emitted when a sub unit is minted into a base unit's TBA.
    /// @dev Emitted at the end of mintSubUnit(), after all state is settled and after any
    ///      BaseUnitCompleted event. `score` equals the 1-indexed slot position at mint time.
    /// @param subUnitId  The token ID of the newly minted sub unit.
    /// @param baseUnitId The base unit whose TBA received this sub unit.
    /// @param tba        The TBA address that now holds this sub unit.
    /// @param score      The score awarded (equals the slot position: first slot = 1, second = 2, etc.).
    event SubUnitMinted(uint256 indexed subUnitId, uint256 indexed baseUnitId, address indexed tba, uint256 score);

    /// @notice Emitted when a base unit fills its final sub unit slot.
    /// @dev Emitted within mintSubUnit() in the EFFECTS section, before the _mint interaction.
    ///      This ordering ensures any callback observer (e.g., an indexer listening on BaseUnitCompleted)
    ///      sees the completion state before the sub unit token is assigned to the TBA.
    /// @param baseUnitId The base unit that just reached full completion.
    /// @param owner      The address that owns the base unit at the moment of completion.
    /// @param finalScore The total accumulated score (sum of all slot scores: 1+2+...+limit).
    event BaseUnitCompleted(uint256 indexed baseUnitId, address indexed owner, uint256 finalScore);

    // --- Constructor ---

    /// @notice Deploys SubUnit bound to a specific BaseUnit contract.
    /// @param _baseUnitContract The deployed BaseUnit.sol address. Must not be zero.
    /// @param _subUnitPrice     Mint price in wei. Exact-match enforced at mint. 0 = free mint.
    /// @param _treasury         Recipient of all mint proceeds. Must not be zero.
    /// @dev Validates that _baseUnitContract has non-zero limits for all three types by calling
    ///      subUnitLimitOf(0/1/2) at deploy time. Per-token limits re-read at each mint.
    ///      Reverts with {InvalidAddress} if _baseUnitContract or _treasury is address(0).
    ///      Reverts with {InvalidLimit} if any type limit returned by BaseUnit is 0.
    constructor(address _baseUnitContract, uint256 _subUnitPrice, address _treasury)
        ERC721("AYA-BLOX-6551-SUB", "BLOX-S")
    {
        if (_baseUnitContract == address(0)) revert InvalidAddress(_baseUnitContract);
        BASE_UNIT_CONTRACT = _baseUnitContract;
        if (IBaseUnit(_baseUnitContract).subUnitLimitOf(0) == 0) revert InvalidLimit(0);
        if (IBaseUnit(_baseUnitContract).subUnitLimitOf(1) == 0) revert InvalidLimit(0);
        if (IBaseUnit(_baseUnitContract).subUnitLimitOf(2) == 0) revert InvalidLimit(0);
        if (_treasury == address(0)) revert InvalidAddress(_treasury);
        SUB_UNIT_PRICE = _subUnitPrice;
        TREASURY = _treasury;
    }

    // --- External Functions ---

    /// @notice Mints a sub unit into the caller's base unit TBA.
    /// @param baseUnitId The base unit to receive the sub unit. Must be minted and owned by caller.
    /// @return subUnitId The globally unique token ID of the newly minted sub unit.
    /// @dev Uses Checks-Effects-Interactions: all state settled before the _mint interaction.
    ///      Score formula: score = subUnitCountPerBase[baseUnitId] + 1 (slot position at mint).
    ///      nonReentrant is an additional safeguard alongside the CEI ordering.
    ///      Reverts with {IncorrectPayment} if msg.value != SUB_UNIT_PRICE.
    ///      Reverts with {BaseUnitNotMinted} if getTba(baseUnitId) returns address(0).
    ///      Reverts with {NotBaseUnitOwner} if msg.sender != ownerOf(baseUnitId).
    ///      Reverts with {BaseUnitSlotsFull} if subUnitCountPerBase[baseUnitId] >= limit.
    ///      Emits {BaseUnitCompleted} if this mint fills the final slot (emitted before _mint).
    ///      Emits {SubUnitMinted} on success.
    ///      All collected ETH forwarded to TREASURY; reverts with {WithdrawFailed} on failure.
    function mintSubUnit(uint256 baseUnitId) external payable nonReentrant returns (uint256 subUnitId) {
        // CHECKS
        if (msg.value != SUB_UNIT_PRICE) revert IncorrectPayment(msg.value, SUB_UNIT_PRICE);
        address tba = IBaseUnit(BASE_UNIT_CONTRACT).getTba(baseUnitId);
        if (tba == address(0)) revert BaseUnitNotMinted(baseUnitId);
        address owner = IBaseUnit(BASE_UNIT_CONTRACT).ownerOf(baseUnitId);
        if (owner != msg.sender) revert NotBaseUnitOwner(msg.sender, baseUnitId);
        uint256 limit = IBaseUnit(BASE_UNIT_CONTRACT).subUnitLimitOf(baseUnitId);
        if (subUnitCountPerBase[baseUnitId] >= limit) {
            revert BaseUnitSlotsFull(baseUnitId, limit);
        }

        // EFFECTS
        uint256 score = subUnitCountPerBase[baseUnitId] + 1;
        unchecked {
            subUnitId = _tokenIdCounter++;
        }
        _parentBaseUnit[subUnitId] = baseUnitId;
        subUnitScore[subUnitId] = score;
        _subUnitsByBase[baseUnitId][subUnitCountPerBase[baseUnitId]] = subUnitId;
        subUnitCountPerBase[baseUnitId]++;
        _baseUnitScore[baseUnitId] += score;

        if (subUnitCountPerBase[baseUnitId] == limit) {
            unchecked {
                totalCompleted++;
            }
            emit BaseUnitCompleted(baseUnitId, owner, _baseUnitScore[baseUnitId]);
        }

        // INTERACTION — _mint used intentionally: TBA is a verified, trusted address. The
        // onERC721Received callback _safeMint would trigger serves no purpose here and would
        // add an unnecessary external call between state settlement and event emission.
        _mint(tba, subUnitId);
        emit SubUnitMinted(subUnitId, baseUnitId, tba, score);
        if (msg.value > 0) {
            (bool ok,) = TREASURY.call{value: msg.value}("");
            if (!ok) revert WithdrawFailed();
        }
    }

    /// @notice Returns the total sub units minted into all base units currently owned by an address.
    /// @param user  The address to query. Returns 0 for address(0).
    /// @return total Sum of subUnitCountPerBase across all base units currently owned by user.
    /// @dev O(n) over user's base unit balance, bounded by MAX_UNITS_PER_WALLET.
    ///      Reflects current ownership — if a base unit is transferred away, its sub units are excluded.
    function totalSubUnitsOwned(address user) external view returns (uint256 total) {
        if (user == address(0)) return 0;
        uint256 count = IBaseUnit(BASE_UNIT_CONTRACT).balanceOf(user);
        for (uint256 i = 0; i < count;) {
            uint256 tokenId = IBaseUnit(BASE_UNIT_CONTRACT).tokenOfOwnerByIndex(user, i);
            total += subUnitCountPerBase[tokenId];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Maximum achievable score for a base unit — sum of 1..limit
    /// @param baseUnitId The base unit to query
    /// @return Maximum score achievable when all slots are filled (limit * (limit + 1) / 2)
    function maxLocalScore(uint256 baseUnitId) external view returns (uint256) {
        uint256 limit = IBaseUnit(BASE_UNIT_CONTRACT).subUnitLimitOf(baseUnitId);
        return (limit * (limit + 1)) / 2;
    }

    /// @notice Returns the accumulated score for a base unit — O(1)
    /// @param baseUnitId The base unit to query. Returns 0 for unminted or empty base units.
    /// @return Accumulated score. 0 for unminted or empty base units.
    /// @dev Direct read of _baseUnitScore[baseUnitId]. Incremented at each sub unit mint.
    function localScore(uint256 baseUnitId) external view returns (uint256) {
        return _baseUnitScore[baseUnitId];
    }

    /// @notice Returns total score across all base units currently owned by user — O(n) bounded by MAX_UNITS_PER_WALLET
    /// @param user The address to query. Returns 0 for address(0).
    /// @return total Sum of localScore for each base unit owned. Always reflects current ownership.
    function globalScore(address user) external view returns (uint256 total) {
        if (user == address(0)) return 0;
        uint256 count = IBaseUnit(BASE_UNIT_CONTRACT).balanceOf(user);
        for (uint256 i = 0; i < count;) {
            uint256 tokenId = IBaseUnit(BASE_UNIT_CONTRACT).tokenOfOwnerByIndex(user, i);
            total += _baseUnitScore[tokenId];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns whether a base unit has all sub unit slots filled
    /// @param baseUnitId The base unit to check. Returns false for unminted or empty base units.
    /// @return True when sub unit count equals the limit — permanently true once reached.
    /// @dev Compares subUnitCountPerBase[baseUnitId] against BASE_UNIT_CONTRACT.subUnitLimitOf(baseUnitId).
    function isCompleted(uint256 baseUnitId) external view returns (bool) {
        uint256 limit = IBaseUnit(BASE_UNIT_CONTRACT).subUnitLimitOf(baseUnitId);
        return subUnitCountPerBase[baseUnitId] == limit;
    }

    /// @notice Returns the parent base unit ID for a sub unit.
    /// @param subUnitId The sub unit token ID to query. Must be minted.
    /// @return The base unit ID this sub unit was minted into.
    /// @dev Reverts with {SubUnitDoesNotExist} if subUnitId has not been minted.
    ///      Guards against silent return of 0 (the default mapping value) for invalid IDs.
    function getParentBaseUnit(uint256 subUnitId) external view returns (uint256) {
        if (_ownerOf(subUnitId) == address(0)) revert SubUnitDoesNotExist(subUnitId);
        return _parentBaseUnit[subUnitId];
    }

    /// @notice Returns the sub unit ID at a given index for a base unit.
    /// @param baseUnitId The base unit to query.
    /// @param index      Zero-based position (0 = first minted, count-1 = last minted).
    /// @return The sub unit token ID at that index.
    /// @dev Reverts with {SubUnitIndexOutOfBounds} if index >= subUnitCountPerBase[baseUnitId].
    ///      Mirrors ERC721Enumerable.tokenOfOwnerByIndex for the base→sub relationship.
    ///      Use subUnitCountPerBase(baseUnitId) to determine the valid index range.
    function subUnitOfBaseByIndex(uint256 baseUnitId, uint256 index) external view returns (uint256) {
        if (index >= subUnitCountPerBase[baseUnitId]) revert SubUnitIndexOutOfBounds(baseUnitId, index);
        return _subUnitsByBase[baseUnitId][index];
    }

    /// @notice Returns all sub unit IDs minted into a base unit in mint order
    /// @param baseUnitId The base unit to query
    /// @return ids All sub unit token IDs. Empty array if no sub units have been minted.
    function getSubUnitsForBase(uint256 baseUnitId) external view returns (uint256[] memory ids) {
        uint256 count = subUnitCountPerBase[baseUnitId];
        ids = new uint256[](count);
        for (uint256 i = 0; i < count;) {
            ids[i] = _subUnitsByBase[baseUnitId][i];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Total number of sub units ever minted across all base units
    /// @return The global sub unit mint count.
    /// @dev Includes all minted IDs globally, regardless of current ownership or base unit.
    function totalSubUnitsMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /// @notice Returns a Base64-encoded JSON metadata URI with a fully on-chain SVG image.
    /// @param tokenId The sub unit token ID.
    /// @return A data URI in the format: `data:application/json;base64,{base64-encoded JSON}`.
    /// @dev Reverts with {SubUnitDoesNotExist} if tokenId has not been minted.
    ///      The SVG image reflects live fill state of the parent base unit at the time of the call —
    ///      the image changes as sibling sub units are minted into the same base unit.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert SubUnitDoesNotExist(tokenId);

        uint256 parentId = _parentBaseUnit[tokenId];
        uint256 score = subUnitScore[tokenId];
        uint256 filled = subUnitCountPerBase[parentId];
        uint256 limit = IBaseUnit(BASE_UNIT_CONTRACT).subUnitLimitOf(parentId);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint8 parentType = uint8(parentId % 3);

        string memory image =
            Base64.encode(bytes(_buildSubUnitSvg(tokenId, parentId, score, filled, limit, parentType)));

        string memory json = string.concat(
            '{"name":"AYA-BLOX-6551-SUB #',
            Strings.toString(tokenId),
            '",',
            '"description":"An AYA-BLOX-6551-SUB NFT permanently bound to AYA-BLOX-6551 #',
            Strings.toString(parentId),
            ". Slot ",
            Strings.toString(score),
            " of ",
            Strings.toString(limit),
            '.",',
            '"attributes":[',
            '{"trait_type":"Parent Base Unit","value":',
            Strings.toString(parentId),
            "},",
            '{"trait_type":"Slot Position","value":',
            Strings.toString(score),
            "},",
            '{"trait_type":"Score","value":',
            Strings.toString(score),
            "},",
            '{"trait_type":"Parent Type","value":',
            Strings.toString(parentType),
            '}],"image":"data:image/svg+xml;base64,',
            image,
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Builds the complete SVG string for a sub unit tokenURI — all inputs pre-read by tokenURI().
    ///      `filled` reflects live fill state of the parent base unit at call time.
    ///      Image changes as sibling sub units are minted (filled count increases).
    function _buildSubUnitSvg(
        uint256 tokenId,
        uint256 parentId,
        uint256 score,
        uint256 filled,
        uint256 limit,
        uint8 parentType
    ) private pure returns (string memory) {
        string memory header = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="400" height="400">',
            '<rect width="400" height="400" fill="#0d0d0d"/>',
            '<text x="20" y="44" font-family="monospace" font-size="18" font-weight="bold" fill="#e0e0e0">AYA-BLOX-6551-SUB #',
            Strings.toString(tokenId),
            "</text>",
            '<line x1="20" y1="56" x2="380" y2="56" stroke="#2a2a2a" stroke-width="1"/>'
        );

        string memory stats = string.concat(
            '<text x="20" y="82" font-family="monospace" font-size="12" fill="#555">POSITION</text>',
            '<text x="90" y="82" font-family="monospace" font-size="12" fill="#555">SCORE</text>',
            '<text x="165" y="82" font-family="monospace" font-size="12" fill="#555">PARENT BASE UNIT</text>',
            '<text x="20" y="114" font-family="monospace" font-size="32" font-weight="bold" fill="#00ff88">',
            Strings.toString(score),
            "</text>",
            '<text x="90" y="114" font-family="monospace" font-size="18" fill="#e0e0e0">',
            Strings.toString(score),
            "</text>",
            '<text x="165" y="114" font-family="monospace" font-size="14" fill="',
            SVGRenderer.typeColor(parentType),
            '">Base #',
            Strings.toString(parentId),
            "</text>"
        );

        string memory grid = string.concat(
            '<text x="20" y="140" font-family="monospace" font-size="11" fill="#444">FILL STATE | BASE #',
            Strings.toString(parentId),
            "</text>",
            SVGRenderer.renderSlots(limit, filled)
        );

        string memory footer = string.concat(
            '<text x="20" y="390" font-family="monospace" font-size="10" fill="#2a2a2a">AYA-BLOX-6551 | ERC-6551 | MINT-ONLY</text>',
            "</svg>"
        );

        return string.concat(header, stats, grid, footer);
    }

    // --- ERC-721 Overrides (approvals disabled) ---

    /// @notice Disabled. Sub units are non-transferable — approvals serve no purpose.
    /// @dev Always reverts with {SubUnitNonTransferable}. Overrides ERC721.approve() to close
    ///      the single-token approval pathway, preventing any approval-based transfer.
    /// @param tokenId The sub unit token for which approval was attempted.
    function approve(address, uint256 tokenId) public pure override {
        revert SubUnitNonTransferable(tokenId);
    }

    /// @notice Disabled. Sub units are non-transferable — operator approvals serve no purpose.
    /// @dev Always reverts with {ApprovalsDisabled}. Overrides ERC721.setApprovalForAll() to close
    ///      the operator approval pathway alongside _update's mint-only guard.
    function setApprovalForAll(
        address,
        /*operator*/
        bool /*approved*/
    )
        public
        pure
        override
    {
        revert ApprovalsDisabled();
    }

    // --- Internal Functions ---

    /// @inheritdoc ERC721
    /// @dev Enforces the mint-only invariant: reverts with {SubUnitNonTransferable} if
    ///      _ownerOf(tokenId) != address(0), meaning the token already has an owner.
    ///      This distinguishes a mint (no prior owner) from a transfer or burn (has owner).
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert SubUnitNonTransferable(tokenId);
        return super._update(to, tokenId, auth);
    }
}
