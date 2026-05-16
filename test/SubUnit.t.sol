// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BaseUnit} from "../src/BaseUnit.sol";
import {
    SubUnit,
    BaseUnitNotMinted,
    NotBaseUnitOwner,
    BaseUnitSlotsFull,
    SubUnitNonTransferable,
    SubUnitDoesNotExist,
    ApprovalsDisabled,
    SubUnitIndexOutOfBounds
} from "../src/SubUnit.sol";
import {MockRegistry} from "./mocks/MockRegistry.sol";
import {InvalidAddress, InvalidLimit, IncorrectPayment, WithdrawFailed} from "../src/errors/Errors.sol";

contract SubUnitTest is Test {
    BaseUnit public baseUnit;
    SubUnit public subUnit;
    MockRegistry public mockRegistry;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal treasury = makeAddr("treasury");

    address internal constant STUB_TBA_IMPL = address(0x1);
    uint256 internal constant LIMIT_0 = 4;
    uint256 internal constant LIMIT_1 = 6;
    uint256 internal constant LIMIT_2 = 8;
    uint256 internal constant MAX_SUPPLY = 100;
    uint256 internal constant MAX_WALLET = 5;

    uint256 internal baseUnitId;
    address internal aliceTba;

    // Declared here to use with vm.expectEmit
    event BaseUnitCompleted(uint256 indexed baseUnitId, address indexed owner, uint256 finalScore);
    event SubUnitMinted(uint256 indexed subUnitId, uint256 indexed baseUnitId, address indexed tba, uint256 score);

    function setUp() public {
        mockRegistry = new MockRegistry();
        baseUnit = new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury
        );
        subUnit = new SubUnit(address(baseUnit), 0, treasury);

        vm.prank(alice);
        baseUnitId = baseUnit.mintBaseUnit(); // token 0 → type 0, limit = LIMIT_0
        aliceTba = baseUnit.getTba(baseUnitId);
    }

    // -------------------------------------------------------------------------
    // Mint — happy paths
    // -------------------------------------------------------------------------

    function test_mintSubUnit_mintsToTBA() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.ownerOf(subUnitId), aliceTba);
    }

    function test_mintSubUnit_recordsParent() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.getParentBaseUnit(subUnitId), baseUnitId);
    }

    function test_mintSubUnit_incrementsCount() public {
        vm.prank(alice);
        subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.subUnitCountPerBase(baseUnitId), 1);
    }

    function test_mintSubUnit_fillsSlots() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        assertEq(subUnit.subUnitCountPerBase(baseUnitId), LIMIT_0);
    }

    function test_isCompleted_trueWhenFull() public {
        assertFalse(subUnit.isCompleted(baseUnitId));

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();

        assertTrue(subUnit.isCompleted(baseUnitId));
    }

    function test_isCompleted_partialFill_returnsFalse() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0 - 1; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        assertFalse(subUnit.isCompleted(baseUnitId));
    }

    // -------------------------------------------------------------------------
    // Mint — revert paths
    // -------------------------------------------------------------------------

    function test_mintSubUnit_slotsFull_reverts() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.expectRevert(abi.encodeWithSelector(BaseUnitSlotsFull.selector, baseUnitId, LIMIT_0));
        subUnit.mintSubUnit(baseUnitId);
        vm.stopPrank();
    }

    function test_mintSubUnit_notOwner_reverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotBaseUnitOwner.selector, bob, baseUnitId));
        subUnit.mintSubUnit(baseUnitId);
    }

    function test_mintSubUnit_unmintedBase_reverts() public {
        uint256 nonExistentId = 999;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BaseUnitNotMinted.selector, nonExistentId));
        subUnit.mintSubUnit(nonExistentId);
    }

    // -------------------------------------------------------------------------
    // Transfer guard — mint-only enforcement
    // -------------------------------------------------------------------------

    function test_transfer_reverts() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);

        vm.prank(aliceTba);
        vm.expectRevert(abi.encodeWithSelector(SubUnitNonTransferable.selector, subUnitId));
        subUnit.transferFrom(aliceTba, bob, subUnitId);
    }

    // -------------------------------------------------------------------------
    // Global ID uniqueness
    // -------------------------------------------------------------------------

    function test_mintSubUnit_uniqueIds() public {
        vm.prank(bob);
        uint256 bobBaseUnitId = baseUnit.mintBaseUnit();

        uint256[8] memory ids;

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            ids[i] = subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();

        vm.startPrank(bob);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            ids[LIMIT_0 + i] = subUnit.mintSubUnit(bobBaseUnitId);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < 8; i++) {
            for (uint256 j = i + 1; j < 8; j++) {
                assertNotEq(ids[i], ids[j]);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Approvals disabled
    // -------------------------------------------------------------------------

    function test_approve_reverts() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);
        vm.expectRevert(abi.encodeWithSelector(SubUnitNonTransferable.selector, subUnitId));
        subUnit.approve(bob, subUnitId);
    }

    function test_setApprovalForAll_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ApprovalsDisabled.selector);
        subUnit.setApprovalForAll(bob, true);
    }

    // -------------------------------------------------------------------------
    // getParentBaseUnit — existence check
    // -------------------------------------------------------------------------

    function test_getParentBaseUnit_returnsParent() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.getParentBaseUnit(subUnitId), baseUnitId);
    }

    function test_getParentBaseUnit_nonExistent_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SubUnitDoesNotExist.selector, uint256(999)));
        subUnit.getParentBaseUnit(999);
    }

    // -------------------------------------------------------------------------
    // Local scoring — position-based
    // -------------------------------------------------------------------------

    function test_subUnitScore_firstSlot() public {
        vm.prank(alice);
        uint256 subUnitId = subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.subUnitScore(subUnitId), 1);
    }

    function test_subUnitScore_byPosition() public {
        uint256[4] memory ids;
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            ids[i] = subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < LIMIT_0; i++) {
            assertEq(subUnit.subUnitScore(ids[i]), i + 1);
        }
    }

    function test_localScore_empty() public view {
        assertEq(subUnit.localScore(999), 0);
    }

    function test_localScore_partialFill() public {
        vm.startPrank(alice);
        subUnit.mintSubUnit(baseUnitId); // score 1
        subUnit.mintSubUnit(baseUnitId); // score 2
        vm.stopPrank();
        assertEq(subUnit.localScore(baseUnitId), 3); // 1 + 2
    }

    function test_localScore_accumulatesCorrectly() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        // LIMIT_0=4: 1+2+3+4 = 10
        uint256 expected = (LIMIT_0 * (LIMIT_0 + 1)) / 2;
        assertEq(subUnit.localScore(baseUnitId), expected);
    }

    // -------------------------------------------------------------------------
    // Global scoring
    // -------------------------------------------------------------------------

    function test_globalScore_empty() public view {
        assertEq(subUnit.globalScore(bob), 0);
    }

    function test_globalScore_zeroAddress() public view {
        assertEq(subUnit.globalScore(address(0)), 0);
    }

    function test_globalScore_singleBase() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        assertEq(subUnit.globalScore(alice), subUnit.localScore(baseUnitId));
    }

    function test_globalScore_multipleBases() public {
        vm.prank(alice);
        uint256 baseUnitId2 = baseUnit.mintBaseUnit();

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId2);
        }
        vm.stopPrank();

        // 4 slots filled for each: 1+2+3+4 = 10 each
        assertEq(subUnit.globalScore(alice), 20);
    }

    // -------------------------------------------------------------------------
    // BaseUnitCompleted event
    // -------------------------------------------------------------------------

    function test_BaseUnitCompleted_emitted() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0 - 1; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        uint256 expectedScore = (LIMIT_0 * (LIMIT_0 + 1)) / 2;
        vm.expectEmit(true, true, false, true);
        emit BaseUnitCompleted(baseUnitId, alice, expectedScore);
        subUnit.mintSubUnit(baseUnitId);
        vm.stopPrank();
    }

    function test_BaseUnitCompleted_notEmittedOnPartialFill() public {
        vm.recordLogs();
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0 - 1; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("BaseUnitCompleted(uint256,address,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(subUnit)) {
                assertNotEq(logs[i].topics[0], sig, "BaseUnitCompleted must not fire on partial fill");
            }
        }
    }

    // -------------------------------------------------------------------------
    // Constructor validation
    // -------------------------------------------------------------------------

    function test_constructor_zeroBaseUnit_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new SubUnit(address(0), 0, treasury);
    }

    function test_constructor_zeroLimitFromBaseUnit_reverts() public {
        MockZeroLimitBaseUnit zeroBase = new MockZeroLimitBaseUnit();
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new SubUnit(address(zeroBase), 0, treasury);
    }

    function test_constructor_zeroType1Limit_reverts() public {
        MockZeroType1LimitBaseUnit mock = new MockZeroType1LimitBaseUnit();
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new SubUnit(address(mock), 0, treasury);
    }

    function test_constructor_zeroType2Limit_reverts() public {
        MockZeroType2LimitBaseUnit mock = new MockZeroType2LimitBaseUnit();
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new SubUnit(address(mock), 0, treasury);
    }

    function test_constructor_zeroTreasury_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new SubUnit(address(baseUnit), 0, address(0));
    }

    // -------------------------------------------------------------------------
    // Type 1 base unit (token ID 1, limit = LIMIT_1 = 6)
    // -------------------------------------------------------------------------

    function test_mintSubUnit_type1_fillsAllSlots() public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1
        assertEq(baseUnit.typeOf(type1BaseId), 1);

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        vm.stopPrank();

        assertEq(subUnit.subUnitCountPerBase(type1BaseId), LIMIT_1);
        assertTrue(subUnit.isCompleted(type1BaseId));
    }

    function test_mintSubUnit_type1_slotsFull_reverts() public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        vm.expectRevert(abi.encodeWithSelector(BaseUnitSlotsFull.selector, type1BaseId, LIMIT_1));
        subUnit.mintSubUnit(type1BaseId);
        vm.stopPrank();
    }

    function test_localScore_type1_fullBase() public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        vm.stopPrank();

        // 1+2+3+4+5+6 = 21
        uint256 expected = (LIMIT_1 * (LIMIT_1 + 1)) / 2;
        assertEq(subUnit.localScore(type1BaseId), expected);
    }

    function test_BaseUnitCompleted_type1_emitted() public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_1 - 1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        uint256 expectedScore = (LIMIT_1 * (LIMIT_1 + 1)) / 2;
        vm.expectEmit(true, true, false, true);
        emit BaseUnitCompleted(type1BaseId, alice, expectedScore);
        subUnit.mintSubUnit(type1BaseId);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Type 2 base unit (token ID 2, limit = LIMIT_2 = 8)
    // -------------------------------------------------------------------------

    function test_mintSubUnit_type2_fillsAllSlots() public {
        vm.prank(alice);
        baseUnit.mintBaseUnit(); // token 1 → type 1 (skip)
        vm.prank(alice);
        uint256 type2BaseId = baseUnit.mintBaseUnit(); // token 2 → type 2
        assertEq(baseUnit.typeOf(type2BaseId), 2);

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_2; i++) {
            subUnit.mintSubUnit(type2BaseId);
        }
        vm.stopPrank();

        assertEq(subUnit.subUnitCountPerBase(type2BaseId), LIMIT_2);
        assertTrue(subUnit.isCompleted(type2BaseId));
    }

    function test_localScore_type2_fullBase() public {
        vm.prank(alice);
        baseUnit.mintBaseUnit(); // token 1 → type 1 (skip)
        vm.prank(alice);
        uint256 type2BaseId = baseUnit.mintBaseUnit(); // token 2 → type 2

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_2; i++) {
            subUnit.mintSubUnit(type2BaseId);
        }
        vm.stopPrank();

        // 1+2+3+4+5+6+7+8 = 36
        uint256 expected = (LIMIT_2 * (LIMIT_2 + 1)) / 2;
        assertEq(subUnit.localScore(type2BaseId), expected);
    }

    // -------------------------------------------------------------------------
    // Global score across mixed types
    // -------------------------------------------------------------------------

    function test_globalScore_mixedTypes() public {
        // alice already has token 0 (type 0, limit 4) from setUp
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        for (uint256 i = 0; i < LIMIT_1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        vm.stopPrank();

        // type 0 full = 1+2+3+4 = 10, type 1 full = 1+2+3+4+5+6 = 21, total = 31
        uint256 expectedType0 = (LIMIT_0 * (LIMIT_0 + 1)) / 2;
        uint256 expectedType1 = (LIMIT_1 * (LIMIT_1 + 1)) / 2;
        assertEq(subUnit.globalScore(alice), expectedType0 + expectedType1);
    }

    // -------------------------------------------------------------------------
    // SubUnitMinted event — score field
    // -------------------------------------------------------------------------

    function test_mintSubUnit_emitsScore() public {
        vm.expectEmit(true, true, true, true);
        emit SubUnitMinted(0, baseUnitId, aliceTba, 1); // first slot → score 1
        vm.prank(alice);
        subUnit.mintSubUnit(baseUnitId);
    }

    function test_mintSubUnit_emitsScore_secondSlot() public {
        vm.startPrank(alice);
        subUnit.mintSubUnit(baseUnitId); // slot 0 → score 1
        vm.expectEmit(true, true, true, true);
        emit SubUnitMinted(1, baseUnitId, aliceTba, 2); // slot 1 → score 2
        subUnit.mintSubUnit(baseUnitId);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Pricing — exact match enforcement
    // -------------------------------------------------------------------------

    function test_mintSubUnit_incorrectPayment_reverts() public {
        SubUnit pricedSub = new SubUnit(address(baseUnit), 0.005 ether, treasury);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IncorrectPayment.selector, uint256(0), uint256(0.005 ether)));
        pricedSub.mintSubUnit(baseUnitId);
    }

    function test_mintSubUnit_excessPayment_reverts() public {
        SubUnit pricedSub = new SubUnit(address(baseUnit), 0.005 ether, treasury);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IncorrectPayment.selector, uint256(0.01 ether), uint256(0.005 ether)));
        pricedSub.mintSubUnit{value: 0.01 ether}(baseUnitId);
    }

    function test_mintSubUnit_correctPayment_succeeds() public {
        SubUnit pricedSub = new SubUnit(address(baseUnit), 0.005 ether, treasury);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 id = pricedSub.mintSubUnit{value: 0.005 ether}(baseUnitId);
        assertEq(pricedSub.ownerOf(id), aliceTba);
    }

    // -------------------------------------------------------------------------
    // Pricing — treasury forwarding (inline, no accumulation)
    // -------------------------------------------------------------------------

    function test_mintSubUnit_forwardsTreasury() public {
        SubUnit pricedSub = new SubUnit(address(baseUnit), 0.005 ether, treasury);
        vm.deal(alice, 1 ether);
        uint256 before = treasury.balance;
        vm.prank(alice);
        pricedSub.mintSubUnit{value: 0.005 ether}(baseUnitId);
        assertEq(treasury.balance, before + 0.005 ether);
        assertEq(address(pricedSub).balance, 0);
    }

    function test_mintSubUnit_brokenTreasury_reverts() public {
        BrokenTreasury broken = new BrokenTreasury();
        SubUnit pricedSub = new SubUnit(address(baseUnit), 0.005 ether, address(broken));
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(WithdrawFailed.selector);
        pricedSub.mintSubUnit{value: 0.005 ether}(baseUnitId);
    }

    // -------------------------------------------------------------------------
    // totalSubUnitsOwned
    // -------------------------------------------------------------------------

    function test_totalSubUnitsOwned_empty() public view {
        assertEq(subUnit.totalSubUnitsOwned(bob), 0);
    }

    function test_totalSubUnitsOwned_zeroAddress() public view {
        assertEq(subUnit.totalSubUnitsOwned(address(0)), 0);
    }

    function test_totalSubUnitsOwned_singleBase() public {
        vm.startPrank(alice);
        subUnit.mintSubUnit(baseUnitId);
        subUnit.mintSubUnit(baseUnitId);
        vm.stopPrank();
        assertEq(subUnit.totalSubUnitsOwned(alice), 2);
    }

    function test_totalSubUnitsOwned_multipleBases() public {
        vm.prank(alice);
        uint256 baseUnitId2 = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        subUnit.mintSubUnit(baseUnitId2);
        subUnit.mintSubUnit(baseUnitId2);
        vm.stopPrank();

        assertEq(subUnit.totalSubUnitsOwned(alice), LIMIT_0 + 2);
    }

    // -------------------------------------------------------------------------
    // maxLocalScore
    // -------------------------------------------------------------------------

    function test_maxLocalScore_type0() public view {
        // token 0 → type 0, limit 4 → max = 1+2+3+4 = 10
        assertEq(subUnit.maxLocalScore(0), 10);
    }

    function test_maxLocalScore_type1() public view {
        // token 1 → type 1, limit 6 → max = 1+2+3+4+5+6 = 21
        assertEq(subUnit.maxLocalScore(1), 21);
    }

    function test_maxLocalScore_type2() public view {
        // token 2 → type 2, limit 8 → max = 1+2+3+4+5+6+7+8 = 36
        assertEq(subUnit.maxLocalScore(2), 36);
    }

    // -------------------------------------------------------------------------
    // tokenURI — on-chain SVG metadata
    // -------------------------------------------------------------------------

    function test_tokenURI_subUnit_returnsDataUri() public {
        vm.prank(alice);
        uint256 subId = subUnit.mintSubUnit(baseUnitId);
        string memory uri = subUnit.tokenURI(subId);

        assertGt(bytes(uri).length, 100);

        bytes memory uriBytes = bytes(uri);
        bytes memory expected = bytes("data:application/json;base64,");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(uriBytes[i], expected[i]);
        }
    }

    function test_tokenURI_subUnit_nonExistent_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SubUnitDoesNotExist.selector, uint256(999)));
        subUnit.tokenURI(999);
    }

    function test_tokenURI_subUnit_allSlotsSucceed() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < LIMIT_0; i++) {
            assertGt(bytes(subUnit.tokenURI(i)).length, 100);
        }
    }

    function test_tokenURI_subUnit_growsWithFill() public {
        vm.startPrank(alice);
        subUnit.mintSubUnit(baseUnitId); // id=0, parent filled=1
        subUnit.mintSubUnit(baseUnitId); // id=1, parent filled=2
        vm.stopPrank();

        // Both sub units must return a valid URI — second mint increases parent fill count
        assertGt(bytes(subUnit.tokenURI(0)).length, 100);
        assertGt(bytes(subUnit.tokenURI(1)).length, 100);
    }

    function test_tokenURI_subUnit_fillStateReflectedInOutput() public {
        vm.prank(alice);
        uint256 subId = subUnit.mintSubUnit(baseUnitId); // parent fill = 1
        bytes32 hashAtFill1 = keccak256(bytes(subUnit.tokenURI(subId)));

        vm.prank(alice);
        subUnit.mintSubUnit(baseUnitId); // parent fill advances to 2

        bytes32 hashAtFill2 = keccak256(bytes(subUnit.tokenURI(subId))); // same token, live state

        // The SVG renderSlots() output changes with fill — URIs must differ
        assertNotEq(hashAtFill1, hashAtFill2);
    }

    // -------------------------------------------------------------------------
    // totalCompleted counter
    // -------------------------------------------------------------------------

    function test_totalCompleted_zeroInitially() public view {
        assertEq(subUnit.totalCompleted(), 0);
    }

    function test_totalCompleted_incrementsOnCompletion() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        assertEq(subUnit.totalCompleted(), 1);
    }

    function test_totalCompleted_noIncrementOnPartialFill() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0 - 1; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        assertEq(subUnit.totalCompleted(), 0);
    }

    function test_totalCompleted_multipleBases() public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1

        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            subUnit.mintSubUnit(baseUnitId);
        }
        for (uint256 i = 0; i < LIMIT_1; i++) {
            subUnit.mintSubUnit(type1BaseId);
        }
        vm.stopPrank();

        assertEq(subUnit.totalCompleted(), 2);
    }

    // -------------------------------------------------------------------------
    // Fuzz — gas target (updated: 200k accounts for scoring SSTOREs)
    // -------------------------------------------------------------------------

    function testFuzz_mintSubUnit_gasUnder225k(uint8 mintCount) public {
        vm.assume(mintCount > 0 && mintCount <= LIMIT_0);
        vm.startPrank(alice);
        for (uint256 i = 0; i < mintCount; i++) {
            uint256 gasStart = gasleft();
            subUnit.mintSubUnit(baseUnitId);
            uint256 gasUsed = gasStart - gasleft();
            assertLt(gasUsed, 225_000, "mintSubUnit exceeds 225k gas target");
        }
        vm.stopPrank();
    }

    function testFuzz_mintSubUnit_type1_gasUnder225k(uint8 mintCount) public {
        vm.prank(alice);
        uint256 type1BaseId = baseUnit.mintBaseUnit(); // token 1 → type 1
        vm.assume(mintCount > 0 && mintCount <= LIMIT_1);
        vm.startPrank(alice);
        for (uint256 i = 0; i < mintCount; i++) {
            uint256 gasStart = gasleft();
            subUnit.mintSubUnit(type1BaseId);
            uint256 gasUsed = gasStart - gasleft();
            assertLt(gasUsed, 225_000, "mintSubUnit type1 exceeds 225k gas target");
        }
        vm.stopPrank();
    }

    function testFuzz_mintSubUnit_type2_gasUnder225k(uint8 mintCount) public {
        vm.prank(alice);
        baseUnit.mintBaseUnit(); // token 1 → type 1 (skip)
        vm.prank(alice);
        uint256 type2BaseId = baseUnit.mintBaseUnit(); // token 2 → type 2
        vm.assume(mintCount > 0 && mintCount <= LIMIT_2);
        vm.startPrank(alice);
        for (uint256 i = 0; i < mintCount; i++) {
            uint256 gasStart = gasleft();
            subUnit.mintSubUnit(type2BaseId);
            uint256 gasUsed = gasStart - gasleft();
            assertLt(gasUsed, 225_000, "mintSubUnit type2 exceeds 225k gas target");
        }
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Sub unit enumeration — subUnitOfBaseByIndex + getSubUnitsForBase
    // -------------------------------------------------------------------------

    function test_subUnitOfBaseByIndex_firstMint() public {
        vm.prank(alice);
        uint256 subId = subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.subUnitOfBaseByIndex(baseUnitId, 0), subId);
    }

    function test_subUnitOfBaseByIndex_mintOrder() public {
        uint256[] memory ids = new uint256[](LIMIT_0);
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            ids[i] = subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        for (uint256 i = 0; i < LIMIT_0; i++) {
            assertEq(subUnit.subUnitOfBaseByIndex(baseUnitId, i), ids[i]);
        }
    }

    function test_subUnitOfBaseByIndex_outOfBounds_reverts() public {
        vm.prank(alice);
        subUnit.mintSubUnit(baseUnitId); // count = 1, valid index = 0 only
        vm.expectRevert(abi.encodeWithSelector(SubUnitIndexOutOfBounds.selector, baseUnitId, uint256(1)));
        subUnit.subUnitOfBaseByIndex(baseUnitId, 1);
    }

    function test_subUnitOfBaseByIndex_unmintedBase_reverts() public {
        uint256 neverMintedBase = 999;
        vm.expectRevert(abi.encodeWithSelector(SubUnitIndexOutOfBounds.selector, neverMintedBase, uint256(0)));
        subUnit.subUnitOfBaseByIndex(neverMintedBase, 0);
    }

    function test_subUnitOfBaseByIndex_multipleBase_noContamination() public {
        vm.prank(bob);
        uint256 bobBaseId = baseUnit.mintBaseUnit(); // token 1

        vm.prank(alice);
        uint256 aliceSubId = subUnit.mintSubUnit(baseUnitId);

        vm.prank(bob);
        uint256 bobSubId = subUnit.mintSubUnit(bobBaseId);

        assertEq(subUnit.subUnitOfBaseByIndex(baseUnitId, 0), aliceSubId);
        assertEq(subUnit.subUnitOfBaseByIndex(bobBaseId, 0), bobSubId);
        assertNotEq(aliceSubId, bobSubId);
    }

    function test_getSubUnitsForBase_empty() public view {
        uint256[] memory ids = subUnit.getSubUnitsForBase(999);
        assertEq(ids.length, 0);
    }

    function test_getSubUnitsForBase_singleMint() public {
        vm.prank(alice);
        uint256 subId = subUnit.mintSubUnit(baseUnitId);
        uint256[] memory ids = subUnit.getSubUnitsForBase(baseUnitId);
        assertEq(ids.length, 1);
        assertEq(ids[0], subId);
    }

    function test_getSubUnitsForBase_fullFill() public {
        uint256[] memory expected = new uint256[](LIMIT_0);
        vm.startPrank(alice);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            expected[i] = subUnit.mintSubUnit(baseUnitId);
        }
        vm.stopPrank();
        uint256[] memory ids = subUnit.getSubUnitsForBase(baseUnitId);
        assertEq(ids.length, LIMIT_0);
        for (uint256 i = 0; i < LIMIT_0; i++) {
            assertEq(ids[i], expected[i]);
        }
    }

    function test_getSubUnitsForBase_multipleBase_isolated() public {
        vm.prank(bob);
        uint256 bobBaseId = baseUnit.mintBaseUnit();

        vm.prank(alice);
        uint256 aliceSubId = subUnit.mintSubUnit(baseUnitId);
        vm.prank(bob);
        uint256 bobSubId = subUnit.mintSubUnit(bobBaseId);

        uint256[] memory aliceIds = subUnit.getSubUnitsForBase(baseUnitId);
        uint256[] memory bobIds = subUnit.getSubUnitsForBase(bobBaseId);

        assertEq(aliceIds.length, 1);
        assertEq(aliceIds[0], aliceSubId);
        assertEq(bobIds.length, 1);
        assertEq(bobIds[0], bobSubId);
    }

    // -------------------------------------------------------------------------
    // totalSubUnitsMinted
    // -------------------------------------------------------------------------

    function test_totalSubUnitsMinted_initial() public view {
        assertEq(subUnit.totalSubUnitsMinted(), 0);
    }

    function test_totalSubUnitsMinted_incrementsPerMint() public {
        assertEq(subUnit.totalSubUnitsMinted(), 0);
        vm.startPrank(alice);
        subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.totalSubUnitsMinted(), 1);
        subUnit.mintSubUnit(baseUnitId);
        assertEq(subUnit.totalSubUnitsMinted(), 2);
        vm.stopPrank();
    }
}

// ---------------------------------------------------------------------------
// Test helper — returns subUnitLimitOf = 0 to exercise SubUnit constructor guard
// ---------------------------------------------------------------------------

contract MockZeroLimitBaseUnit {
    function subUnitLimitOf(uint256) external pure returns (uint256) {
        return 0;
    }

    function ownerOf(uint256) external pure returns (address) {
        return address(0);
    }

    function getTba(uint256) external pure returns (address) {
        return address(0);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Type 1 limit = 0 — passes type 0 check, fails type 1 check
// ---------------------------------------------------------------------------

contract MockZeroType1LimitBaseUnit {
    function subUnitLimitOf(uint256 tokenId) external pure returns (uint256) {
        if (tokenId == 1) return 0;
        return 4;
    }

    function ownerOf(uint256) external pure returns (address) {
        return address(0);
    }

    function getTba(uint256) external pure returns (address) {
        return address(0);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Type 2 limit = 0 — passes type 0 and 1 checks, fails type 2 check
// ---------------------------------------------------------------------------

contract MockZeroType2LimitBaseUnit {
    function subUnitLimitOf(uint256 tokenId) external pure returns (uint256) {
        if (tokenId == 2) return 0;
        return 4;
    }

    function ownerOf(uint256) external pure returns (address) {
        return address(0);
    }

    function getTba(uint256) external pure returns (address) {
        return address(0);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Rejects all ETH — used to exercise the WithdrawFailed revert path
// ---------------------------------------------------------------------------

contract BrokenTreasury {
    receive() external payable {
        revert("BrokenTreasury: rejects ETH");
    }
}
