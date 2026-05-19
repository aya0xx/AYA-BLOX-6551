// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {ERC6551Registry} from "erc6551/ERC6551Registry.sol";
import {ERC6551Account} from "erc6551/examples/simple/ERC6551Account.sol";
import {BaseUnit} from "../src/BaseUnit.sol";
import {SubUnit} from "../src/SubUnit.sol";

/// @title DeployAnvil
/// @author AYA0X
/// @notice Deploys the full AYA-BLOX-6551 system to a local Anvil chain for development and testing.
/// @dev Deploys ERC6551Registry and ERC6551Account from source — Anvil has no canonical deployments.
///      For mainnet deployments, use the canonical registry and TBA implementation addresses directly.
///
///      Usage:
///        cp .env.example .env   # first time only
///        source .env
///        forge script script/DeployAnvil.s.sol \
///          --rpc-url $ANVIL_RPC_URL \
///          --private-key $ANVIL_PRIVATE_KEY \
///          --broadcast
contract DeployAnvil is Script {
    /// @dev Deployment parameters. Mirror the constructor arguments expected by BaseUnit and SubUnit.
    ///      MAX_SUPPLY is set to 1000 for local testing — well below the mainnet value of 10_000.
    uint256 constant TYPE_LIMIT_0 = 4;
    uint256 constant TYPE_LIMIT_1 = 6;
    uint256 constant TYPE_LIMIT_2 = 8;
    uint256 constant MAX_SUPPLY = 1000;
    uint256 constant MAX_UNITS_PER_WALLET = 5;
    uint256 constant BASE_UNIT_PRICE = 0.0003 ether;
    uint256 constant SUB_UNIT_PRICE = 0.0001 ether;

    /// @notice Deploys the full AYA-BLOX-6551 system to the local Anvil chain.
    /// @dev Reads TREASURY_ADDRESS from the environment. Deploys ERC6551Registry,
    ///      ERC6551Account, BaseUnit, and SubUnit in dependency order.
    ///      All deployments are broadcast — run with --broadcast to submit transactions.
    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast();

        // Deploy ERC-6551 infrastructure (Anvil only — no canonical addresses here)
        ERC6551Registry registry = new ERC6551Registry();
        ERC6551Account tbaImpl = new ERC6551Account();

        // Deploy AYA-BLOX-6551 contracts
        BaseUnit baseUnit = new BaseUnit(
            address(tbaImpl),
            address(registry),
            TYPE_LIMIT_0,
            TYPE_LIMIT_1,
            TYPE_LIMIT_2,
            MAX_SUPPLY,
            MAX_UNITS_PER_WALLET,
            BASE_UNIT_PRICE,
            treasury
        );

        SubUnit subUnit = new SubUnit(address(baseUnit), SUB_UNIT_PRICE, treasury);

        vm.stopBroadcast();

        console.log("=== ANVIL DEPLOYMENT COMPLETE ===");
        console.log("Registry:  ", address(registry));
        console.log("TBA Impl:  ", address(tbaImpl));
        console.log("BaseUnit:  ", address(baseUnit));
        console.log("SubUnit:   ", address(subUnit));
        console.log("Treasury:  ", treasury);
        console.log("Chain ID:  ", block.chainid);
    }
}
