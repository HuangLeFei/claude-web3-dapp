// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { ExampleToken } from "../../src/ExampleToken.sol";

contract ExampleTokenTest is Test {
    ExampleToken public token;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public zero = address(0);

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    // ============ 初始化 ============

    function setUp() public {
        vm.prank(owner);
        token = new ExampleToken(owner, INITIAL_SUPPLY);
    }

    // ============ 部署验证 ============

    function test_deploy_initialState() public view {
        assertEq(token.name(), "ExampleToken");
        assertEq(token.symbol(), "EXT");
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
    }

    // ============ mint 函数测试 ============

    function test_mint_byOwner_success() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(owner);
        token.mint(user, amount);
        assertEq(token.balanceOf(user), amount);
    }

    function test_mint_byNonOwner_reverts() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1000);
    }

    function test_mint_exceedsMaxSupply_reverts() public {
        uint256 excess = token.MAX_SUPPLY() - token.totalSupply() + 1;
        vm.prank(owner);
        vm.expectRevert();
        token.mint(user, excess);
    }

    // ============ Fuzz 测试 ============

    function testFuzz_mint_validAmount(uint256 amount) public {
        uint256 remaining = token.MAX_SUPPLY() - token.totalSupply();
        amount = bound(amount, 1, remaining);

        vm.prank(owner);
        token.mint(user, amount);
        assertEq(token.balanceOf(user), amount);
    }
}
