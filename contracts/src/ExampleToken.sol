// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ExampleToken
/// @author Your Project
/// @notice 示例 ERC-20 Token，支持 Permit（EIP-2612）
/// @dev 基于 OpenZeppelin v5，按需扩展
contract ExampleToken is ERC20, ERC20Permit, Ownable {
    // ============ 错误定义 ============
    error ExceedsMaxSupply(uint256 requested, uint256 available);

    // ============ 常量 ============
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 10亿

    // ============ 构造函数 ============

    /// @param initialOwner 初始 owner 地址
    /// @param initialSupply 初始铸造数量（wei）
    constructor(
        address initialOwner,
        uint256 initialSupply
    ) ERC20("ExampleToken", "EXT") ERC20Permit("ExampleToken") Ownable(initialOwner) {
        if (initialSupply > MAX_SUPPLY) {
            revert ExceedsMaxSupply(initialSupply, MAX_SUPPLY);
        }
        _mint(initialOwner, initialSupply);
    }

    // ============ 外部函数 ============

    /// @notice 铸造代币（仅 owner）
    /// @param to 接收地址
    /// @param amount 铸造数量（wei）
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(amount, MAX_SUPPLY - totalSupply());
        }
        _mint(to, amount);
    }
}
