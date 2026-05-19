// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC6551Registry} from "erc6551/interfaces/IERC6551Registry.sol";

/// @dev Test mock — returns a deterministic address for createAccount without deploying anything.
///      Allows BaseUnit unit tests to run without forking a live network.
contract MockRegistry is IERC6551Registry {
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external pure returns (address) {
        return _compute(implementation, salt, chainId, tokenContract, tokenId);
    }

    function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        external
        pure
        returns (address)
    {
        return _compute(implementation, salt, chainId, tokenContract, tokenId);
    }

    function _compute(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        internal
        pure
        returns (address)
    {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(implementation, salt, chainId, tokenContract, tokenId))))
            );
    }
}
