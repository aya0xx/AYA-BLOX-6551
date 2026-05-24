// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {BaseUnit, CannotTransferToTBA, MaxSupplyReached, WalletLimitReached} from "../src/BaseUnit.sol";
import {MockRegistry} from "./mocks/MockRegistry.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {InvalidAddress, InvalidLimit, IncorrectPayment, WithdrawFailed} from "../src/errors/Errors.sol";

contract BaseUnitTest is Test {
    BaseUnit public baseUnit;
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

    event BaseUnitMinted(uint256 indexed tokenId, address indexed owner, address tba, uint8 indexed unitType);

    function setUp() public {
        mockRegistry = new MockRegistry();
        baseUnit = new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury
        );
    }

    // -------------------------------------------------------------------------
    // Mint — happy paths
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_mintsNFT() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        assertEq(baseUnit.ownerOf(id), alice);
    }

    function test_mintBaseUnit_createsTBA() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        assertNotEq(baseUnit.getTba(id), address(0));
    }

    function test_mintBaseUnit_tbaDeterministic() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();

        address expected = mockRegistry.account(STUB_TBA_IMPL, bytes32(0), block.chainid, address(baseUnit), id);
        assertEq(baseUnit.getTba(id), expected);
    }

    function test_mintBaseUnit_multipleAllowed() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_WALLET; i++) {
            uint256 id = baseUnit.mintBaseUnit();
            assertEq(baseUnit.ownerOf(id), alice);
        }
        vm.stopPrank();
    }

    function test_mintBaseUnit_uniqueTBAs() public {
        address[5] memory tbas;
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_WALLET; i++) {
            uint256 id = baseUnit.mintBaseUnit();
            tbas[i] = baseUnit.getTba(id);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < MAX_WALLET; i++) {
            for (uint256 j = i + 1; j < MAX_WALLET; j++) {
                assertNotEq(tbas[i], tbas[j]);
            }
        }
    }

    // -------------------------------------------------------------------------
    // TBA transfer guard
    // -------------------------------------------------------------------------

    function test_selfNesting_reverts() public {
        vm.startPrank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        address tba = baseUnit.getTba(id);
        vm.expectRevert(abi.encodeWithSelector(CannotTransferToTBA.selector, id, tba));
        baseUnit.transferFrom(alice, tba, id);
        vm.stopPrank();
    }

    function test_crossTokenNesting_reverts() public {
        vm.startPrank(alice);
        uint256 idA = baseUnit.mintBaseUnit();
        uint256 idB = baseUnit.mintBaseUnit();
        address tbaB = baseUnit.getTba(idB);
        vm.expectRevert(abi.encodeWithSelector(CannotTransferToTBA.selector, idA, tbaB));
        baseUnit.transferFrom(alice, tbaB, idA);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // isTba — TBA address recognition
    // -------------------------------------------------------------------------

    function test_isTba_returnsTrueForTba() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        assertTrue(baseUnit.isTba(baseUnit.getTba(id)));
    }

    function test_isTba_returnsFalseForEOA() public view {
        assertFalse(baseUnit.isTba(alice));
    }

    function test_isTba_returnsFalseForZeroAddress() public view {
        assertFalse(baseUnit.isTba(address(0)));
    }

    function test_isTba_distinctTbasAllRecognised() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit();
        uint256 id1 = baseUnit.mintBaseUnit();
        vm.stopPrank();
        assertTrue(baseUnit.isTba(baseUnit.getTba(id0)));
        assertTrue(baseUnit.isTba(baseUnit.getTba(id1)));
    }

    function test_isTba_returnsFalseForNonTbaContract() public view {
        assertFalse(baseUnit.isTba(address(baseUnit)));
    }

    function test_isTba_returnsFalseBeforeMint() public {
        address expectedTba = mockRegistry.account(STUB_TBA_IMPL, bytes32(0), block.chainid, address(baseUnit), 0);
        assertFalse(baseUnit.isTba(expectedTba));
        vm.prank(alice);
        baseUnit.mintBaseUnit();
        assertTrue(baseUnit.isTba(expectedTba));
    }

    // -------------------------------------------------------------------------
    // getTba — dedicated view tests
    // -------------------------------------------------------------------------

    function test_getTba_unminted_returnsZero() public view {
        assertEq(baseUnit.getTba(999), address(0));
    }

    function test_getTba_multipleTokens_eachCorrect() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit();
        uint256 id1 = baseUnit.mintBaseUnit();
        uint256 id2 = baseUnit.mintBaseUnit();
        vm.stopPrank();
        assertEq(baseUnit.getTba(id0), mockRegistry.account(STUB_TBA_IMPL, bytes32(0), block.chainid, address(baseUnit), id0));
        assertEq(baseUnit.getTba(id1), mockRegistry.account(STUB_TBA_IMPL, bytes32(0), block.chainid, address(baseUnit), id1));
        assertEq(baseUnit.getTba(id2), mockRegistry.account(STUB_TBA_IMPL, bytes32(0), block.chainid, address(baseUnit), id2));
    }

    // -------------------------------------------------------------------------
    // Supply cap
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_supplyReached_reverts() public {
        BaseUnit localBase =
            new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, 3, 3, 0, treasury);
        vm.startPrank(alice);
        localBase.mintBaseUnit();
        localBase.mintBaseUnit();
        localBase.mintBaseUnit();
        vm.expectRevert(abi.encodeWithSelector(MaxSupplyReached.selector, uint256(3)));
        localBase.mintBaseUnit();
        vm.stopPrank();
    }

    function test_totalSupply_incrementsOnMint() public {
        assertEq(baseUnit.totalSupply(), 0);
        vm.prank(alice);
        baseUnit.mintBaseUnit();
        assertEq(baseUnit.totalSupply(), 1);
        vm.prank(alice);
        baseUnit.mintBaseUnit();
        assertEq(baseUnit.totalSupply(), 2);
    }

    // -------------------------------------------------------------------------
    // Wallet holding cap
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_walletLimitReached_reverts() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_WALLET; i++) {
            baseUnit.mintBaseUnit();
        }
        vm.expectRevert(abi.encodeWithSelector(WalletLimitReached.selector, alice, uint256(MAX_WALLET)));
        baseUnit.mintBaseUnit();
        vm.stopPrank();
    }

    function test_transfer_walletLimitReached_reverts() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_WALLET; i++) {
            baseUnit.mintBaseUnit();
        }
        vm.stopPrank();

        vm.prank(bob);
        uint256 bobId = baseUnit.mintBaseUnit();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(WalletLimitReached.selector, alice, uint256(MAX_WALLET)));
        baseUnit.transferFrom(bob, alice, bobId);
    }

    // -------------------------------------------------------------------------
    // ERC721Enumerable
    // -------------------------------------------------------------------------

    function test_tokenOfOwnerByIndex_correct() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit();
        uint256 id1 = baseUnit.mintBaseUnit();
        vm.stopPrank();

        assertEq(baseUnit.tokenOfOwnerByIndex(alice, 0), id0);
        assertEq(baseUnit.tokenOfOwnerByIndex(alice, 1), id1);
    }

    // -------------------------------------------------------------------------
    // Constructor validation
    // -------------------------------------------------------------------------

    function test_constructor_zeroImpl_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new BaseUnit(address(0), address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury);
    }

    function test_constructor_zeroRegistry_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new BaseUnit(STUB_TBA_IMPL, address(0), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury);
    }

    function test_constructor_zeroTreasury_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, address(0)
        );
    }

    function test_constructor_zeroLimit_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), 0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury);
    }

    function test_constructor_zeroMaxSupply_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, 0, MAX_WALLET, 0, treasury);
    }

    function test_constructor_zeroWalletLimit_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, 0, 0, treasury);
    }

    function test_constructor_walletLimitExceedsSupply_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(10)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, 5, 10, 0, treasury);
    }

    // -------------------------------------------------------------------------
    // ERC165 interface support
    // -------------------------------------------------------------------------

    function test_supportsInterface_erc721() public view {
        assertTrue(baseUnit.supportsInterface(type(IERC721).interfaceId));
    }

    function test_supportsInterface_erc721Enumerable() public view {
        assertTrue(baseUnit.supportsInterface(type(IERC721Enumerable).interfaceId));
    }

    function test_supportsInterface_erc165() public view {
        assertTrue(baseUnit.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_invalidId_returnsFalse() public view {
        assertFalse(baseUnit.supportsInterface(0xdeadbeef));
    }

    // -------------------------------------------------------------------------
    // Type rotation
    // -------------------------------------------------------------------------

    function test_typeOf_rotation() public view {
        assertEq(baseUnit.typeOf(0), 0);
        assertEq(baseUnit.typeOf(1), 1);
        assertEq(baseUnit.typeOf(2), 2);
        assertEq(baseUnit.typeOf(3), 0);
        assertEq(baseUnit.typeOf(4), 1);
        assertEq(baseUnit.typeOf(5), 2);
    }

    function test_subUnitLimitOf_type0() public view {
        assertEq(baseUnit.subUnitLimitOf(0), LIMIT_0);
    }

    function test_subUnitLimitOf_type1() public view {
        assertEq(baseUnit.subUnitLimitOf(1), LIMIT_1);
    }

    function test_subUnitLimitOf_type2() public view {
        assertEq(baseUnit.subUnitLimitOf(2), LIMIT_2);
    }

    // -------------------------------------------------------------------------
    // Constructor validation — per-type limits
    // -------------------------------------------------------------------------

    function test_constructor_zeroTypeLimit1_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, 0, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0, treasury);
    }

    function test_constructor_zeroTypeLimit2_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLimit.selector, uint256(0)));
        new BaseUnit(STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, 0, MAX_SUPPLY, MAX_WALLET, 0, treasury);
    }

    // -------------------------------------------------------------------------
    // BaseUnitMinted event includes type
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_emitsType() public {
        vm.expectEmit(true, true, true, false);
        emit BaseUnitMinted(0, alice, address(0), 0); // token 0 → type 0
        vm.prank(alice);
        baseUnit.mintBaseUnit();
    }

    // -------------------------------------------------------------------------
    // Burn guard — base units are non-burnable
    // -------------------------------------------------------------------------

    function test_burn_reverts() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        vm.prank(alice);
        vm.expectRevert();
        baseUnit.transferFrom(alice, address(0), id);
    }

    // -------------------------------------------------------------------------
    // Pricing — exact match enforcement
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_incorrectPayment_reverts() public {
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL,
            address(mockRegistry),
            LIMIT_0,
            LIMIT_1,
            LIMIT_2,
            MAX_SUPPLY,
            MAX_WALLET,
            0.01 ether,
            treasury
        );
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IncorrectPayment.selector, uint256(0), uint256(0.01 ether)));
        pricedBase.mintBaseUnit();
    }

    function test_mintBaseUnit_excessPayment_reverts() public {
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL,
            address(mockRegistry),
            LIMIT_0,
            LIMIT_1,
            LIMIT_2,
            MAX_SUPPLY,
            MAX_WALLET,
            0.01 ether,
            treasury
        );
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IncorrectPayment.selector, uint256(0.02 ether), uint256(0.01 ether)));
        pricedBase.mintBaseUnit{value: 0.02 ether}();
    }

    function test_mintBaseUnit_correctPayment_succeeds() public {
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL,
            address(mockRegistry),
            LIMIT_0,
            LIMIT_1,
            LIMIT_2,
            MAX_SUPPLY,
            MAX_WALLET,
            0.01 ether,
            treasury
        );
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        uint256 id = pricedBase.mintBaseUnit{value: 0.01 ether}();
        assertEq(pricedBase.ownerOf(id), alice);
    }

    // -------------------------------------------------------------------------
    // Pricing — treasury forwarding (inline, no accumulation)
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_forwardsTreasury() public {
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL,
            address(mockRegistry),
            LIMIT_0,
            LIMIT_1,
            LIMIT_2,
            MAX_SUPPLY,
            MAX_WALLET,
            0.01 ether,
            treasury
        );
        vm.deal(alice, 1 ether);
        uint256 before = treasury.balance;
        vm.prank(alice);
        pricedBase.mintBaseUnit{value: 0.01 ether}();
        assertEq(treasury.balance, before + 0.01 ether);
        assertEq(address(pricedBase).balance, 0);
    }

    function test_mintBaseUnit_brokenTreasury_reverts() public {
        BrokenTreasury broken = new BrokenTreasury();
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL,
            address(mockRegistry),
            LIMIT_0,
            LIMIT_1,
            LIMIT_2,
            MAX_SUPPLY,
            MAX_WALLET,
            0.01 ether,
            address(broken)
        );
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(WithdrawFailed.selector);
        pricedBase.mintBaseUnit{value: 0.01 ether}();
    }

    // -------------------------------------------------------------------------
    // typeBalanceOf
    // -------------------------------------------------------------------------

    function test_typeBalanceOf_empty() public view {
        assertEq(baseUnit.typeBalanceOf(alice, 0), 0);
    }

    function test_typeBalanceOf_mixedWallet() public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // token 0 → type 0
        baseUnit.mintBaseUnit(); // token 1 → type 1
        baseUnit.mintBaseUnit(); // token 2 → type 2
        baseUnit.mintBaseUnit(); // token 3 → type 0
        vm.stopPrank();

        assertEq(baseUnit.typeBalanceOf(alice, 0), 2);
        assertEq(baseUnit.typeBalanceOf(alice, 1), 1);
        assertEq(baseUnit.typeBalanceOf(alice, 2), 1);
    }

    function test_typeBalanceOf_afterTransfer() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit(); // token 0 → type 0
        baseUnit.mintBaseUnit(); // token 1 → type 1 (alice keeps)
        vm.stopPrank();

        assertEq(baseUnit.typeBalanceOf(alice, 0), 1);
        assertEq(baseUnit.typeBalanceOf(bob, 0), 0);

        vm.prank(alice);
        baseUnit.transferFrom(alice, bob, id0); // transfer type 0 to bob

        assertEq(baseUnit.typeBalanceOf(alice, 0), 0);
        assertEq(baseUnit.typeBalanceOf(bob, 0), 1);
        assertEq(baseUnit.typeBalanceOf(alice, 1), 1); // unaffected
    }

    function test_typeBalanceOf_zeroAddress_reverts() public {
        vm.expectRevert();
        baseUnit.typeBalanceOf(address(0), 0);
    }

    function test_typeBalanceOf_allSameType() public {
        address carol = makeAddr("carol");
        // Mint tokens 0, 3, 6 for alice (all type 0)
        // carol mints tokens 1, 2 and 4, 5 in between to advance the counter
        vm.prank(alice); baseUnit.mintBaseUnit(); // token 0 → type 0
        vm.startPrank(carol);
        baseUnit.mintBaseUnit(); // token 1 → type 1
        baseUnit.mintBaseUnit(); // token 2 → type 2
        vm.stopPrank();
        vm.prank(alice); baseUnit.mintBaseUnit(); // token 3 → type 0
        vm.startPrank(carol);
        baseUnit.mintBaseUnit(); // token 4 → type 1
        baseUnit.mintBaseUnit(); // token 5 → type 2
        vm.stopPrank();
        vm.prank(alice); baseUnit.mintBaseUnit(); // token 6 → type 0

        assertEq(baseUnit.typeBalanceOf(alice, 0), 3);
        assertEq(baseUnit.typeBalanceOf(alice, 1), 0);
        assertEq(baseUnit.typeBalanceOf(alice, 2), 0);
    }

    function test_typeBalanceOf_invalidType_returnsZero() public {
        vm.prank(alice);
        baseUnit.mintBaseUnit(); // token 0 → type 0
        assertEq(baseUnit.typeBalanceOf(alice, 3), 0);
    }

    function testFuzz_typeBalanceOf_neverExceedsBalance(uint8 unitType) public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // type 0
        baseUnit.mintBaseUnit(); // type 1
        baseUnit.mintBaseUnit(); // type 2
        vm.stopPrank();
        assertLe(baseUnit.typeBalanceOf(alice, unitType), baseUnit.balanceOf(alice));
    }

    // -------------------------------------------------------------------------
    // tokenURI — on-chain SVG metadata
    // -------------------------------------------------------------------------

    function test_tokenURI_baseUnit_returnsDataUri() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        string memory uri = baseUnit.tokenURI(id);

        assertGt(bytes(uri).length, 100);

        bytes memory uriBytes = bytes(uri);
        bytes memory expected = bytes("data:application/json;base64,");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(uriBytes[i], expected[i]);
        }
    }

    function test_tokenURI_baseUnit_allTypesSucceed() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit(); // type 0
        uint256 id1 = baseUnit.mintBaseUnit(); // type 1
        uint256 id2 = baseUnit.mintBaseUnit(); // type 2
        vm.stopPrank();

        assertGt(bytes(baseUnit.tokenURI(id0)).length, 100);
        assertGt(bytes(baseUnit.tokenURI(id1)).length, 100);
        assertGt(bytes(baseUnit.tokenURI(id2)).length, 100);
    }

    function test_tokenURI_baseUnit_nonExistent_reverts() public {
        vm.expectRevert();
        baseUnit.tokenURI(999);
    }

    function test_tokenURI_baseUnit_typeProducesDistinctOutput() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit(); // type 0
        uint256 id1 = baseUnit.mintBaseUnit(); // type 1
        uint256 id2 = baseUnit.mintBaseUnit(); // type 2
        vm.stopPrank();

        bytes32 hash0 = keccak256(bytes(baseUnit.tokenURI(id0)));
        bytes32 hash1 = keccak256(bytes(baseUnit.tokenURI(id1)));
        bytes32 hash2 = keccak256(bytes(baseUnit.tokenURI(id2)));

        assertNotEq(hash0, hash1);
        assertNotEq(hash1, hash2);
        assertNotEq(hash0, hash2);
    }

    function test_tokenURI_baseUnit_outputIsStatic() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        bytes32 hash1 = keccak256(bytes(baseUnit.tokenURI(id)));
        bytes32 hash2 = keccak256(bytes(baseUnit.tokenURI(id)));
        assertEq(hash1, hash2);
    }

    function test_tokenURI_baseUnit_slotCountReflectedAcrossTypes() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit(); // type 0, LIMIT_0 = 4 slots
        baseUnit.mintBaseUnit();               // type 1 (skip)
        uint256 id2 = baseUnit.mintBaseUnit(); // type 2, LIMIT_2 = 8 slots
        vm.stopPrank();
        assertNotEq(
            keccak256(bytes(baseUnit.tokenURI(id0))),
            keccak256(bytes(baseUnit.tokenURI(id2)))
        );
    }

    // -------------------------------------------------------------------------
    // Fuzz — gas target (updated: 300k accounts for ERC721Enumerable overhead)
    // -------------------------------------------------------------------------

    function testFuzz_mintBaseUnit_gasUnder300k(uint8 mintCount) public {
        vm.assume(mintCount > 0 && mintCount <= MAX_WALLET);
        address user = makeAddr("fuzzer");
        vm.startPrank(user);
        for (uint256 i = 0; i < mintCount; i++) {
            uint256 gasStart = gasleft();
            baseUnit.mintBaseUnit();
            uint256 gasUsed = gasStart - gasleft();
            assertLt(gasUsed, 300_000, "mintBaseUnit exceeds 300k gas target");
        }
        vm.stopPrank();
    }

    function test_mintBaseUnit_firstTokenIdIsZero() public {
        vm.prank(alice);
        uint256 id = baseUnit.mintBaseUnit();
        assertEq(id, 0);
    }

    function test_mintBaseUnit_tokenIdsSequential() public {
        vm.startPrank(alice);
        uint256 id0 = baseUnit.mintBaseUnit();
        uint256 id1 = baseUnit.mintBaseUnit();
        uint256 id2 = baseUnit.mintBaseUnit();
        vm.stopPrank();
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_mintBaseUnit_freeMint_noTreasuryForward() public {
        // setUp deploys with BASE_UNIT_PRICE = 0; treasury call is skipped
        uint256 before = treasury.balance;
        vm.prank(alice);
        baseUnit.mintBaseUnit();
        assertEq(treasury.balance, before);
    }

    // -------------------------------------------------------------------------
    // Immutable getter return values — all 9 constructor params
    // -------------------------------------------------------------------------

    function test_tbaImplementation_returnsConstructorValue() public view {
        assertEq(baseUnit.TBA_IMPLEMENTATION(), STUB_TBA_IMPL);
    }

    function test_registry_returnsConstructorValue() public view {
        assertEq(address(baseUnit.REGISTRY()), address(mockRegistry));
    }

    function test_subUnitLimit0_returnsConstructorValue() public view {
        assertEq(baseUnit.TYPE_LIMIT_0(), LIMIT_0);
    }

    function test_subUnitLimit1_returnsConstructorValue() public view {
        assertEq(baseUnit.TYPE_LIMIT_1(), LIMIT_1);
    }

    function test_subUnitLimit2_returnsConstructorValue() public view {
        assertEq(baseUnit.TYPE_LIMIT_2(), LIMIT_2);
    }

    function test_maxSupply_returnsConstructorValue() public view {
        assertEq(baseUnit.MAX_SUPPLY(), MAX_SUPPLY);
    }

    function test_maxWallet_returnsConstructorValue() public view {
        assertEq(baseUnit.MAX_UNITS_PER_WALLET(), MAX_WALLET);
    }

    function test_mintPrice_returnsConstructorValue() public view {
        assertEq(baseUnit.BASE_UNIT_PRICE(), 0);
    }

    function test_treasury_returnsConstructorValue() public view {
        assertEq(baseUnit.TREASURY(), treasury);
    }

    function test_name_returnsCorrectValue() public view {
        assertEq(baseUnit.name(), "AYA-BLOX-6551");
    }

    function test_symbol_returnsCorrectValue() public view {
        assertEq(baseUnit.symbol(), "BLOX");
    }

    function test_constructor_nonZeroPriceStored() public {
        BaseUnit pricedBase = new BaseUnit(
            STUB_TBA_IMPL, address(mockRegistry), LIMIT_0, LIMIT_1, LIMIT_2, MAX_SUPPLY, MAX_WALLET, 0.01 ether, treasury
        );
        assertEq(pricedBase.BASE_UNIT_PRICE(), 0.01 ether);
    }

    // -------------------------------------------------------------------------
    // Transfer — to TBA reverts, to non-TBA succeeds, TBA mapping preserved
    // -------------------------------------------------------------------------

    function test_transfer_toTba_reverts() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit();
        address tba = baseUnit.getTba(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CannotTransferToTBA.selector, tokenId, tba));
        baseUnit.transferFrom(alice, tba, tokenId);
    }

    function test_transfer_toNonTba_succeeds() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit();

        vm.prank(alice);
        baseUnit.transferFrom(alice, bob, tokenId);

        assertEq(baseUnit.ownerOf(tokenId), bob);
    }

    function test_transfer_tbaMappingPreserved() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit();
        address tba = baseUnit.getTba(tokenId);

        vm.prank(alice);
        baseUnit.transferFrom(alice, bob, tokenId);

        assertEq(baseUnit.getTba(tokenId), tba);
    }

    function test_safeTransferFrom_toTba_reverts() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit();
        address tba = baseUnit.getTba(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CannotTransferToTBA.selector, tokenId, tba));
        baseUnit.safeTransferFrom(alice, tba, tokenId);
    }

    function test_transfer_approvedOperator_succeeds() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit();

        vm.prank(alice);
        baseUnit.approve(bob, tokenId);

        vm.prank(bob);
        baseUnit.transferFrom(alice, bob, tokenId);

        assertEq(baseUnit.ownerOf(tokenId), bob);
    }

    // -------------------------------------------------------------------------
    // typeOf — all three types
    // -------------------------------------------------------------------------

    function test_typeOf_tokenZero_returnsType0() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 0 → 0 % 3 == 0
        assertEq(baseUnit.typeOf(tokenId), 0);
    }

    function test_typeOf_tokenOne_returnsType1() public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // token 0
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 1 → 1 % 3 == 1
        vm.stopPrank();
        assertEq(baseUnit.typeOf(tokenId), 1);
    }

    function test_typeOf_tokenTwo_returnsType2() public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // token 0
        baseUnit.mintBaseUnit(); // token 1
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 2 → 2 % 3 == 2
        vm.stopPrank();
        assertEq(baseUnit.typeOf(tokenId), 2);
    }

    function testFuzz_typeOf_alwaysZeroOneOrTwo(uint256 tokenId) public view {
        assertTrue(baseUnit.typeOf(tokenId) <= 2);
    }

    // -------------------------------------------------------------------------
    // subUnitLimitOf — routes to correct limit by type
    // -------------------------------------------------------------------------

    function test_subUnitLimitOf_type0_returnsLimit0() public {
        vm.prank(alice);
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 0 → type 0
        assertEq(baseUnit.subUnitLimitOf(tokenId), LIMIT_0);
    }

    function test_subUnitLimitOf_type1_returnsLimit1() public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // token 0
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 1 → type 1
        vm.stopPrank();
        assertEq(baseUnit.subUnitLimitOf(tokenId), LIMIT_1);
    }

    function test_subUnitLimitOf_type2_returnsLimit2() public {
        vm.startPrank(alice);
        baseUnit.mintBaseUnit(); // token 0
        baseUnit.mintBaseUnit(); // token 1
        uint256 tokenId = baseUnit.mintBaseUnit(); // token 2 → type 2
        vm.stopPrank();
        assertEq(baseUnit.subUnitLimitOf(tokenId), LIMIT_2);
    }

    function test_subUnitLimitOf_unmintedId_safeToCall() public view {
        // 999 % 3 == 0 → LIMIT_0; no ownership check, no revert
        assertEq(baseUnit.subUnitLimitOf(999), LIMIT_0);
    }

    function test_subUnitLimitOf_wrapAround() public view {
        assertEq(baseUnit.subUnitLimitOf(3), LIMIT_0); // 3 % 3 == 0
        assertEq(baseUnit.subUnitLimitOf(4), LIMIT_1); // 4 % 3 == 1
        assertEq(baseUnit.subUnitLimitOf(5), LIMIT_2); // 5 % 3 == 2
    }

    function testFuzz_subUnitLimitOf_routingCorrect(uint256 tokenId) public view {
        uint256 result = baseUnit.subUnitLimitOf(tokenId);
        uint256 t = tokenId % 3;
        if (t == 0) assertEq(result, LIMIT_0);
        else if (t == 1) assertEq(result, LIMIT_1);
        else assertEq(result, LIMIT_2);
    }

    // -------------------------------------------------------------------------
    // Multi-user — independent wallet limits and shared supply counter
    // -------------------------------------------------------------------------

    function test_mintBaseUnit_multipleUsers_eachReceivesDistinctToken() public {
        vm.prank(alice);
        uint256 aliceId = baseUnit.mintBaseUnit();
        vm.prank(bob);
        uint256 bobId = baseUnit.mintBaseUnit();

        assertNotEq(aliceId, bobId);
        assertEq(baseUnit.ownerOf(aliceId), alice);
        assertEq(baseUnit.ownerOf(bobId), bob);
    }

    function test_walletLimit_isPerUser_notGlobal() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < MAX_WALLET; i++) {
            baseUnit.mintBaseUnit();
        }
        vm.stopPrank();

        // alice is at wallet cap, bob should still mint freely
        vm.prank(bob);
        uint256 bobId = baseUnit.mintBaseUnit();
        assertEq(baseUnit.ownerOf(bobId), bob);
    }

    function test_totalSupply_accumulatesAcrossUsers() public {
        vm.prank(alice);
        baseUnit.mintBaseUnit();
        vm.prank(bob);
        baseUnit.mintBaseUnit();

        assertEq(baseUnit.totalSupply(), 2);
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
