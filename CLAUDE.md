# DApp 智能合约项目 - Claude Code 主控规则

## 项目概述

本项目为去中心化应用（DApp）开发工作区，涵盖智能合约编写、前端集成与全流程质量保障。

## Agent 团队组成

| Agent | 职责 | 触发场景 |
|---|---|---|
| `pm-agent` | 需求分析、PRD、任务拆解 | 新功能讨论、需求评审 |
| `architect-agent` | 技术架构、合约设计、ADR | 方案设计、技术选型 |
| `contract-dev-agent` | 智能合约开发、部署脚本 | 合约编写、链上交互 |
| `security-agent` | 安全审计、漏洞扫描 | 合约完成后、上线前必须执行 |
| `tester-agent` | 单元测试、集成测试、覆盖率 | 合约修改后自动触发 |

## Sub-Agent 调度规则

### 并行执行（以下条件全部满足时）
- 3 个以上独立任务，无共享状态
- 文件边界明确，无重叠修改
- 示例：前端组件开发 + 测试脚本编写 + 文档更新

### 串行执行（满足任意条件时）
- 任务存在依赖关系（B 需要 A 的输出）
- 共享文件或链上状态
- 示例：`pm-agent` → `architect-agent` → `contract-dev-agent` → `security-agent` → `tester-agent`

### 标准开发流水线

```
需求输入
  └─► pm-agent（PRD + 任务列表）
        └─► architect-agent（技术设计 + ADR）
              └─► contract-dev-agent（合约实现）
                    ├─► security-agent（安全审计）
                    └─► tester-agent（测试套件）
```

## 文档规范

所有产出文件保存位置：

- **需求 / PRD**：`docs/requirements/YYYY-MM-DD/`
- **技术设计 / ADR**：`docs/architecture/YYYY-MM-DD/`
- **安全审计报告**：`docs/audit/YYYY-MM-DD/`
- **合约规格**：`docs/specs/`
- **合约代码**：`contracts/src/`
- **测试文件**：`contracts/test/`
- **部署脚本**：`contracts/scripts/` 和 `scripts/deploy/`
- **前端源码**：`frontend/src/`

## 技术栈约定

- **合约框架**：Foundry（优先）或 Hardhat
- **合约语言**：Solidity ^0.8.20
- **合约标准**：OpenZeppelin v5
- **前端框架**：Next.js + TypeScript
- **Web3 库**：wagmi v2 + viem v2
- **测试覆盖率目标**：≥ 90%
- **安全标准**：通过 security-agent 审计后方可提交 PR

## 命名规范

- 合约文件：`PascalCase.sol`
- 测试文件：`ContractName.t.sol`（Foundry）或 `ContractName.test.ts`
- 部署脚本：`Deploy_ContractName.s.sol`
- 前端 hooks：`use-contract-name.ts`
- ABI 文件：`ContractName.abi.json`

## 质量门禁

在提交任何合约代码前，必须满足：

1. `tester-agent` 测试全部通过，覆盖率 ≥ 90%
2. `security-agent` 审计无高危漏洞
3. 所有公开函数有 NatSpec 注释
4. 合约大小 < 24KB（EIP-170 限制）
