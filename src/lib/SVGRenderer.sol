// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SVGRenderer
/// @author AYA0X.ETH
/// @notice Pure SVG building utilities for on-chain BaseUnit and SubUnit token metadata.
library SVGRenderer {
    uint256 private constant BOX_SIZE    = 36;
    uint256 private constant BOX_GAP     = 8;
    uint256 private constant GRID_X      = 20;
    uint256 private constant GRID_Y      = 155;
    uint256 private constant COLS_PER_ROW = 4;

    /// @notice Renders a slot grid as concatenated SVG rect and text elements.
    /// @param limit  Total number of slots. Determines grid height.
    /// @param filled Number of slots to render as filled. Must be <= limit. 0 = all empty.
    /// @return result Concatenated SVG markup. Embed directly inside a parent `<svg>` element.
    /// @dev Grid is COLS_PER_ROW columns wide.
    ///      Filled slots render with a green fill (#00ff88) and a 1-indexed number label.
    ///      Empty slots render with a dark fill (#1a1a1a) and no label.
    function renderSlots(uint256 limit, uint256 filled) internal pure returns (string memory result) {
        for (uint256 i = 0; i < limit;) {
            uint256 x = GRID_X + (i % COLS_PER_ROW) * (BOX_SIZE + BOX_GAP);
            // forge-lint: disable-next-line(divide-before-multiply)
            uint256 y = GRID_Y + (i / COLS_PER_ROW) * (BOX_SIZE + BOX_GAP);
            bool on = i < filled;

            result = string.concat(
                result,
                '<rect x="',
                Strings.toString(x),
                '" y="',
                Strings.toString(y),
                '" width="',
                Strings.toString(BOX_SIZE),
                '" height="',
                Strings.toString(BOX_SIZE),
                '" fill="',
                on ? "#00ff88" : "#1a1a1a",
                '" stroke="',
                on ? "#00ff88" : "#2a2a2a",
                '" stroke-width="1" rx="3"/>'
            );

            if (on) {
                result = string.concat(
                    result,
                    '<text x="',
                    Strings.toString(x + BOX_SIZE / 2),
                    '" y="',
                    Strings.toString(y + BOX_SIZE / 2 + 5),
                    '" font-family="monospace" font-size="13"',
                    ' fill="#0d0d0d" text-anchor="middle">',
                    Strings.toString(i + 1),
                    "</text>"
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the SVG hex color string for a base unit type.
    /// @param unitType The unit type. Expected values: 0, 1, or 2.
    /// @return Hex color string: "#666666" (type 0), "#999999" (type 1), "#cccccc" (type 2 or default).
    /// @dev Falls through to "#cccccc" for any value other than 0 or 1.
    function typeColor(uint8 unitType) internal pure returns (string memory) {
        if (unitType == 0) return "#666666";
        if (unitType == 1) return "#999999";
        return "#cccccc";
    }
}
