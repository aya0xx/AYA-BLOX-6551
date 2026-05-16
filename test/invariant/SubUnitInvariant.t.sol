// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {BaseUnit} from "../../src/BaseUnit.sol";
import {SubUnit} from "../../src/SubUnit.sol";
import {MockRegistry} from "../mocks/MockRegistry.sol";

// ---------------------------------------------------------------------------
// Handler — constrains the call space for invariant fuzzing.
// Only these three functions are called by the fuzzer (via targetContract).
// Guard conditions prevent reverts so the fuzzer explores state, not errors.
// Ghost state tracks minted base IDs so invariant checks can iterate them.
// ---------------------------------------------------------------------------

contract InvariantHandler is Test {
    BaseUnit internal baseUnit;
    SubUnit internal subUnit;

    address[] internal actors;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[] public ghost_mintedBaseIds;

    uint256 internal constant MAX_WALLET = 5;
    uint256 internal constant MAX_SUPPLY = 50;

    constructor(BaseUnit _baseUnit, SubUnit _subUnit) {
        baseUnit = _baseUnit;
        subUnit = _subUnit;
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));
        for (uint256 i = 0; i < actors.length; i++) {
            vm.deal(actors[i], 100 ether);
        }
    }

    /// @dev Mint a base unit for a randomly-selected actor.
    ///      Guards: actor below MAX_WALLET, global supply below MAX_SUPPLY.
    function mintBase(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        if (baseUnit.balanceOf(actor) >= MAX_WALLET) return;
        if (baseUnit.totalSupply() >= MAX_SUPPLY) return;

        vm.prank(actor);
        uint256 id = baseUnit.mintBaseUnit();
        ghost_mintedBaseIds.push(id);
    }

    /// @dev Mint a sub unit into a randomly-selected base unit.
    ///      Guards: at least one base minted, selected base has open slots,
    ///              caller is the current owner of the base unit.
    function mintSub(uint256 baseIdSeed) external {
        if (ghost_mintedBaseIds.length == 0) return;
        uint256 baseId = ghost_mintedBaseIds[baseIdSeed % ghost_mintedBaseIds.length];
        uint256 limit = baseUnit.subUnitLimitOf(baseId);
        if (subUnit.subUnitCountPerBase(baseId) >= limit) return;

        address owner = baseUnit.ownerOf(baseId);
        vm.prank(owner);
        subUnit.mintSubUnit(baseId);
    }

    /// @dev Transfer a base unit between actors.
    ///      Guards: recipient below MAX_WALLET, recipient is not a TBA,
    ///              recipient is different from current owner.
    function transferBase(uint256 actorSeed, uint256 baseIdSeed) external {
        if (ghost_mintedBaseIds.length == 0) return;
        uint256 baseId = ghost_mintedBaseIds[baseIdSeed % ghost_mintedBaseIds.length];
        address from = baseUnit.ownerOf(baseId);
        address to = actors[(actorSeed + 1) % actors.length];

        if (to == from) return;
        if (baseUnit.balanceOf(to) >= MAX_WALLET) return;
        if (baseUnit.isTba(to)) return;

        vm.prank(from);
        baseUnit.transferFrom(from, to, baseId);
    }

    /// @dev Accessor for ghost array length — used by invariant loops.
    function mintedBaseCount() external view returns (uint256) {
        return ghost_mintedBaseIds.length;
    }
}

// ---------------------------------------------------------------------------
// Invariant test contract — 6 invariants across BaseUnit and SubUnit.
// ---------------------------------------------------------------------------

contract SubUnitInvariantTest is Test {
    BaseUnit internal baseUnit;
    SubUnit internal subUnit;
    MockRegistry internal mockRegistry;
    InvariantHandler internal handler;

    address internal treasury = makeAddr("treasury");
    address internal constant STUB_TBA_IMPL = address(0x1);

    uint256 internal constant LIMIT_0 = 4;
    uint256 internal constant LIMIT_1 = 6;
    uint256 internal constant LIMIT_2 = 8;
    uint256 internal constant MAX_SUPPLY = 50;
    uint256 internal constant MAX_WALLET = 5;

    function setUp() public {
        mockRegistry = new MockRegistry();
        baseUnit = new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury
        );
        subUnit = new SubUnit(address(baseUnit), 0, treasury);
        handler = new InvariantHandler(baseUnit, subUnit);

        targetContract(address(handler));
    }

    // -------------------------------------------------------------------------
    // I-1 — Slot cap: subUnitCountPerBase[id] never exceeds subUnitLimitOf(id)
    // -------------------------------------------------------------------------
    // This is the core game mechanic invariant. If breached, a completed base
    // unit would accept additional sub units, corrupting the score and the
    // completed state permanently.

    function invariant_slotCapNeverExceeded() public view {
        uint256 count = handler.mintedBaseCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 baseId = handler.ghost_mintedBaseIds(i);
            uint256 limit = baseUnit.subUnitLimitOf(baseId);
            assertLe(subUnit.subUnitCountPerBase(baseId), limit, "I-1: slot cap exceeded");
        }
    }

    // -------------------------------------------------------------------------
    // I-2 — Score integrity: localScore[id] == triangular sum of count
    // -------------------------------------------------------------------------
    // Score formula at mint: score = position + 1 (1-based).
    // Accumulated score for n minted sub units = 1+2+...+n = n*(n+1)/2.
    // If any score write is wrong, this invariant catches it.

    function invariant_scoreIntegrity() public view {
        uint256 count = handler.mintedBaseCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 baseId = handler.ghost_mintedBaseIds(i);
            uint256 filled = subUnit.subUnitCountPerBase(baseId);
            uint256 expectedScore = (filled * (filled + 1)) / 2;
            assertEq(subUnit.localScore(baseId), expectedScore, "I-2: localScore does not match triangular sum");
        }
    }

    // -------------------------------------------------------------------------
    // I-3 — Completion accuracy: totalCompleted matches the actual completed count
    // -------------------------------------------------------------------------
    // totalCompleted is a public uint256 incremented in mintSubUnit when a base
    // fills its last slot. This invariant verifies it always equals the true
    // count of fully-filled bases — stronger than checking monotonicity alone.

    function invariant_totalCompletedAccurate() public view {
        uint256 count = handler.mintedBaseCount();
        uint256 actualCompleted = 0;
        for (uint256 i = 0; i < count; i++) {
            uint256 baseId = handler.ghost_mintedBaseIds(i);
            uint256 limit = baseUnit.subUnitLimitOf(baseId);
            if (subUnit.subUnitCountPerBase(baseId) == limit) {
                actualCompleted++;
            }
        }
        assertEq(
            subUnit.totalCompleted(), actualCompleted, "I-3: totalCompleted does not match actual completed base count"
        );
    }

    // -------------------------------------------------------------------------
    // I-4 — Enumeration consistency: index map agrees with ownership
    // -------------------------------------------------------------------------
    // subUnitOfBaseByIndex(baseId, i) must return a token owned by the base's TBA
    // for every valid index i in [0, subUnitCountPerBase(baseId)).
    // If the _subUnitsByBase mapping and subUnitCountPerBase diverge at any point,
    // the UI would silently display wrong data or throw an out-of-bounds revert.

    function invariant_enumerationConsistency() public view {
        uint256 count = handler.mintedBaseCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 baseId = handler.ghost_mintedBaseIds(i);
            uint256 filled = subUnit.subUnitCountPerBase(baseId);
            address tba = baseUnit.getTba(baseId);
            for (uint256 j = 0; j < filled; j++) {
                uint256 subId = subUnit.subUnitOfBaseByIndex(baseId, j);
                assertEq(subUnit.ownerOf(subId), tba, "I-4: enumerated sub unit not owned by base TBA");
            }
        }
    }

    // -------------------------------------------------------------------------
    // I-5 — Supply cap: totalSupply() never exceeds MAX_SUPPLY
    // -------------------------------------------------------------------------
    // The hard cap is checked in mintBaseUnit before the counter increment.
    // This invariant confirms the ERC721Enumerable totalSupply() always stays
    // within the configured bound under arbitrary mint sequences.

    function invariant_supplyCapNeverExceeded() public view {
        assertLe(baseUnit.totalSupply(), MAX_SUPPLY, "I-5: totalSupply exceeds MAX_SUPPLY");
    }

    // -------------------------------------------------------------------------
    // I-6 — TBA registry integrity: every minted token's TBA is recognized
    // -------------------------------------------------------------------------
    // isTba(getTba(id)) must be true for every minted base unit.
    // The SubUnit mint guard uses isTba to verify the TBA destination.
    // If this invariant breaks, SubUnit.mintSubUnit would revert for that base
    // even though the base is valid — bricking the game loop for that token.

    function invariant_tbaMappingConsistency() public view {
        uint256 count = handler.mintedBaseCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 baseId = handler.ghost_mintedBaseIds(i);
            address tba = baseUnit.getTba(baseId);
            assertTrue(baseUnit.isTba(tba), "I-6: minted token TBA not recognized by isTba");
        }
    }
}
