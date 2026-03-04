# DApp 智能合约项目

基于 Claude Code Agent Teams 驱动的 DApp 全栈开发工作区。

## Agent 团队

| Agent | 触发方式 |
|---|---|
| `pm-agent` | 提出新需求时自动调用 |
| `architect-agent` | PRD 完成后自动调用 |
| `contract-dev-agent` | 架构设计完成后自动调用 |
| `security-agent` | 合约编写完成后**必须**调用 |
| `tester-agent` | 安全审计通过后自动调用 |

## 快速开始

### 启动新功能开发

```
/new-feature 描述你的功能需求
```

### 单独执行审计

```
/audit
/audit contracts/src/MyContract.sol
```

### 运行测试

```
/test
/test coverage
```

## 技术栈

- **合约**：Solidity ^0.8.20 + OpenZeppelin v5 + Foundry
- **前端**：Next.js 14 + TypeScript + wagmi v2 + viem v2
- **测试**：Foundry（合约）+ Vitest（前端）

## 项目结构

```
.
├── .claude/
│   ├── agents/               # Sub-Agent 定义
│   └── commands/             # 自定义斜杠命令
├── contracts/
│   ├── src/                  # 合约源码
│   ├── test/                 # 测试文件
│   │   ├── unit/
│   │   ├── fuzz/
│   │   ├── invariant/
│   │   └── integration/
│   ├── scripts/              # 部署脚本（Foundry）
│   └── lib/                  # 依赖库
├── frontend/
│   └── src/
│       ├── components/       # React 组件
│       ├── hooks/            # 自定义 hooks
│       ├── pages/            # 页面
│       ├── abis/             # 合约 ABI
│       ├── types/            # TypeScript 类型
│       └── utils/            # 工具函数
├── docs/
│   ├── requirements/         # PRD 文档
│   ├── architecture/         # ADR 架构决策
│   ├── audit/                # 安全审计报告
│   └── specs/                # 合约规格文档
├── scripts/
│   ├── deploy/               # 部署脚本（TS）
│   ├── verify/               # 合约验证脚本
│   └── utils/                # 工具脚本
├── CLAUDE.md                 # Agent 主控规则
├── foundry.toml              # Foundry 配置
└── .env.example              # 环境变量模板
```

## 开发规范

详见 `CLAUDE.md`。
