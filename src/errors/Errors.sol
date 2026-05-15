// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @notice Address argument is zero.
/// @dev Thrown in BaseUnit and SubUnit constructors for every address immutable.
///      A zero address at deployment means the contract is permanently broken with no admin surface.
/// @param provided The zero address that was supplied.
error InvalidAddress(address provided);

/// @notice Limit argument is zero.
/// @dev Thrown in BaseUnit constructor for type limits, maxSupply, maxUnitsPerWallet.
///      Thrown in SubUnit constructor if any BaseUnit type limit returns zero.
///      A zero limit would make minting impossible and cannot be corrected post-deploy.
/// @param provided The zero value that was supplied.
error InvalidLimit(uint256 provided);

/// @notice ETH sent does not match the required mint price — exact match enforced.
/// @dev Thrown in BaseUnit.mintBaseUnit() and SubUnit.mintSubUnit().
///      Exact-match enforces predictable pricing — no overpayment or underpayment accepted.
/// @param sent     Amount sent by the caller, in wei.
/// @param required The exact amount required by the contract, in wei.
error IncorrectPayment(uint256 sent, uint256 required);

/// @notice ETH transfer to the treasury failed.
/// @dev Thrown in BaseUnit.mintBaseUnit() and SubUnit.mintSubUnit() when the low-level
///      TREASURY.call{value}("") returns false. Prevents ETH from remaining trapped in the contract.
error WithdrawFailed();
