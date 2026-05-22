// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {BaseUnit} from "../../src/BaseUnit.sol";
import {MockRegistry} from "../mocks/MockRegistry.sol";

// ---------------------------------------------------------------------------
// Handler — BaseUnit-only fuzzing surface.
// Constrains the call space to mint and transfer; no SubUnit dependency.
// Ghost state tracks all minted token IDs for invariant iteration.
// ---------------------------------------------------------------------------

contract BaseUnitHandler is Test {
    BaseUnit internal baseUnit;

    address[] internal actors;

    // forge-lint: disable-next-line(mixed-case-variable)
    uint256[] public ghost_mintedIds;

    uint256 internal constant MAX_WALLET = 5;
    uint256 internal constant MAX_SUPPLY = 50;

    constructor(BaseUnit _baseUnit) {
        baseUnit = _baseUnit;
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
        ghost_mintedIds.push(id);
    }

    /// @dev Transfer a base unit between actors.
    ///      Guards: recipient below MAX_WALLET, recipient is not a TBA.
    function transferBase(uint256 actorSeed, uint256 tokenSeed) external {
        if (ghost_mintedIds.length == 0) return;
        uint256 tokenId = ghost_mintedIds[tokenSeed % ghost_mintedIds.length];
        address from = baseUnit.ownerOf(tokenId);
        address to = actors[(actorSeed + 1) % actors.length];

        if (to == from) return;
        if (baseUnit.balanceOf(to) >= MAX_WALLET) return;
        if (baseUnit.isTba(to)) return;

        vm.prank(from);
        baseUnit.transferFrom(from, to, tokenId);
    }

    /// @dev Accessor for ghost array length — used by invariant loops.
    function mintedCount() external view returns (uint256) {
        return ghost_mintedIds.length;
    }
}

// ---------------------------------------------------------------------------
// Invariant test contract — 7 invariants over BaseUnit state.
// ---------------------------------------------------------------------------

contract BaseUnitInvariantTest is Test {
    BaseUnit internal baseUnit;
    MockRegistry internal mockRegistry;
    BaseUnitHandler internal handler;

    address internal treasury = makeAddr("treasury");
    address internal constant STUB_TBA_IMPL = address(0x1);

    uint256 internal constant LIMIT_0 = 4;
    uint256 internal constant LIMIT_1 = 6;
    uint256 internal constant LIMIT_2 = 8;
    uint256 internal constant MAX_SUPPLY = 50;
    uint256 internal constant MAX_WALLET = 5;

    // Precomputed in setUp so invariant view functions can reference them
    address internal actor0;
    address internal actor1;
    address internal actor2;
    address internal actor3;

    function setUp() public {
        actor0 = makeAddr("alice");
        actor1 = makeAddr("bob");
        actor2 = makeAddr("carol");
        actor3 = makeAddr("dave");
        mockRegistry = new MockRegistry();
        baseUnit = new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury
        );
        handler = new BaseUnitHandler(baseUnit);

        targetContract(address(handler));
    }

    // -------------------------------------------------------------------------
    // B-1 — Supply cap: totalSupply() never exceeds MAX_SUPPLY
    // -------------------------------------------------------------------------
    // The mintBaseUnit guard checks totalSupply() < MAX_SUPPLY before minting.
    // If the counter ever diverges, the cap is silently bypassed.

    function invariant_supplyNeverExceedsMax() public view {
        assertLe(baseUnit.totalSupply(), MAX_SUPPLY, "B-1: totalSupply exceeds MAX_SUPPLY");
    }

    // -------------------------------------------------------------------------
    // B-2 — Wallet limit: balanceOf(actor) never exceeds MAX_WALLET
    // -------------------------------------------------------------------------
    // Enforced per-address before every mint. If breached, the minting guard
    // failed to fire for that actor.

    function invariant_walletLimitNeverExceeded() public view {
        assertLe(baseUnit.balanceOf(actor0), MAX_WALLET, "B-2: wallet limit exceeded for alice");
        assertLe(baseUnit.balanceOf(actor1), MAX_WALLET, "B-2: wallet limit exceeded for bob");
        assertLe(baseUnit.balanceOf(actor2), MAX_WALLET, "B-2: wallet limit exceeded for carol");
        assertLe(baseUnit.balanceOf(actor3), MAX_WALLET, "B-2: wallet limit exceeded for dave");
    }

    // -------------------------------------------------------------------------
    // B-3 — TBA always deployed: getTba returns non-zero for every minted token
    // -------------------------------------------------------------------------
    // The registry creates a TBA for each minted base unit inside mintBaseUnit.
    // A zero TBA address would brick the SubUnit mint guard permanently for that
    // token since isTba(address(0)) is always false.

    function invariant_tbaAlwaysNonZero() public view {
        uint256 count = handler.mintedCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = handler.ghost_mintedIds(i);
            assertNotEq(baseUnit.getTba(tokenId), address(0), "B-3: getTba returned zero");
        }
    }

    // -------------------------------------------------------------------------
    // B-4 — isTba recognizes every registered TBA
    // -------------------------------------------------------------------------
    // isTba is the guard used by SubUnit.mintSubUnit. It must return true for
    // every address produced by getTba; otherwise valid TBAs would be rejected.

    function invariant_isTbaRecognizesAllTbas() public view {
        uint256 count = handler.mintedCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = handler.ghost_mintedIds(i);
            address tba = baseUnit.getTba(tokenId);
            assertTrue(baseUnit.isTba(tba), "B-4: getTba address not recognized by isTba");
        }
    }

    // -------------------------------------------------------------------------
    // B-5 — typeOf returns a valid type (0, 1, or 2) for every minted token
    // -------------------------------------------------------------------------
    // typeOf = tokenId % 3. The result must be one of the three valid types;
    // any other value would corrupt subUnitLimitOf routing.

    function invariant_typeIsAlwaysZeroOneOrTwo() public view {
        uint256 count = handler.mintedCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = handler.ghost_mintedIds(i);
            uint8 t = baseUnit.typeOf(tokenId);
            assertTrue(t <= 2, "B-5: typeOf returned value outside {0,1,2}");
        }
    }

    // -------------------------------------------------------------------------
    // B-6 — subUnitLimitOf routes correctly for all three types
    // -------------------------------------------------------------------------
    // subUnitLimitOf must return the constructor-configured limit for each type.
    // A wrong routing would give the wrong slot cap to the SubUnit mint guard.

    function invariant_subUnitLimitMatchesType() public view {
        uint256 count = handler.mintedCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = handler.ghost_mintedIds(i);
            uint8 t = baseUnit.typeOf(tokenId);
            uint256 limit = baseUnit.subUnitLimitOf(tokenId);
            if (t == 0) assertEq(limit, LIMIT_0, "B-6: type 0 limit mismatch");
            else if (t == 1) assertEq(limit, LIMIT_1, "B-6: type 1 limit mismatch");
            else assertEq(limit, LIMIT_2, "B-6: type 2 limit mismatch");
        }
    }

    // -------------------------------------------------------------------------
    // B-7 — Enumeration consistency: ghost count matches totalSupply
    // -------------------------------------------------------------------------
    // The handler ghost array length must equal baseUnit.totalSupply().
    // A divergence would mean either the ghost is miscounting or ERC721Enumerable
    // has an unreachable mint path that bypasses the ghost.

    function invariant_enumerationConsistency() public view {
        assertEq(baseUnit.totalSupply(), handler.mintedCount(), "B-7: totalSupply diverges from ghost mint count");
    }
}
