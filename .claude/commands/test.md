# 测试命令

运行测试套件并输出覆盖率报告。

## 使用方式

```
/test [测试类型] [目标]
/test                             # 运行所有测试
/test unit                        # 仅单元测试
/test fuzz                        # 仅 Fuzz 测试
/test coverage                    # 测试 + 覆盖率报告
/test contracts/test/MyToken.t.sol  # 指定测试文件
```

## 执行步骤

1. 调用 `tester-agent` 执行对应测试
2. 解析测试结果，高亮失败用例
3. 生成覆盖率报告，检查是否达到 90% 目标
4. 输出 Gas 快照对比（如有历史快照）
