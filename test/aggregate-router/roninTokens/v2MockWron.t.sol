// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { MockERC20 } from "../mock/MockERC20.sol";
import { KatanaV2Test } from "../KatanaV2.t.sol";

contract V2MockWron is KatanaV2Test {
  MockERC20 mock;

  function setUpTokens() internal override {
    mock = new MockERC20();
  }

  function token0() internal pure override returns (address) {
    return address(WETH9);
  }

  function token1() internal view override returns (address) {
    return address(mock);
  }
}