# 安全审计命令

对指定合约或整个 contracts/src/ 目录执行安全审计。

## 使用方式

```
/audit [合约文件路径]
/audit                  # 审计所有合约
/audit contracts/src/MyToken.sol
```

## 执行步骤

1. 调用 `security-agent` 对目标合约执行完整审计
2. 输出审计报告至 `docs/audit/YYYY-MM-DD/`
3. 高危漏洞：阻断后续流程，列出必须修复的项目
4. 通过审计：通知 tester-agent 可以开始测试
