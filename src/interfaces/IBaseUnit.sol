// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/// @title IBaseUnit
/// @notice Interface SubUnit needs from BaseUnit — ownership, TBA resolution, type limits, and enumeration.
/// @dev Inherits IERC721Enumerable so ownerOf, balanceOf, and tokenOfOwnerByIndex
///      are available without re-declaration. Only TBA-specific and type-limit functions are declared here.
///      Implemented by BaseUnit.sol. SubUnit reads through this interface only — no circular dependency.
interface IBaseUnit is IERC721Enumerable {
    /// @notice Returns the TBA address for a base unit.
    /// @param tokenId The base unit token ID to query. Works for any ID — returns address(0) if unminted.
    /// @return The deterministic TBA wallet address, or address(0) if the token has not been minted.
    /// @dev The address is computed once at mint via REGISTRY.account() and cached in BaseUnit storage.
    ///      Callers must treat address(0) as "not minted" — SubUnit.mintSubUnit() reverts on this case.
    function getTba(uint256 tokenId) external view returns (address);

    /// @notice Returns the sub unit slot limit for a base unit's type.
    /// @param tokenId The base unit token ID to query. Minted or unminted — limit is deterministic from ID.
    /// @return The maximum number of sub units that can be minted into this token.
    /// @dev Pure derivation from tokenId % 3: type 0 → TYPE_LIMIT_0, type 1 → TYPE_LIMIT_1, type 2 → TYPE_LIMIT_2.
    ///      Safe to call for unminted token IDs — does not check ownership or existence.
    function subUnitLimitOf(uint256 tokenId) external view returns (uint256);
}
