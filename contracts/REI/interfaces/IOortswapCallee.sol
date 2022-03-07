
// SPDX-License-Identifier: MIT
pragma solidity =0.5.17;

interface IOortswapCallee {
    function OortswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}