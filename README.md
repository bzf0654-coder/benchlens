# benchlens

> A lens for LLM inference benchmarks —— 推理基准结果的"透镜"：一条命令，把散落的 benchmark 数字变成可读的对比结论。

## 解决什么问题

做大模型推理优化（vLLM / SGLang / 国产算力适配）的人，每天都在产出基准数据：TTFT、TPOT、吞吐、延迟分位数……但两轮实验之间到底提升了多少，往往要靠手工翻日志、复制进 Excel 再手搓公式。数字散、口径乱、结论难复现。

benchlens 把这件事变成一条流水线：**读入长表 CSV → 分组统计 → 双 run 对比 → 输出 Markdown 报告**，直接贴进 PR 描述或周报。

## 当前功能（v0.1）

- **CSV 长表解析**：`run,metric,value` 三列格式，自动跳过表头、空行、脏数据
- **分组统计**：按 (run, metric) 分组，计算样本数 n、均值、p50、p99、最小/最大值
- **双 run 对比**：按指标名对齐两个 run，计算相对变化百分比
- **Markdown 表输出**：GitHub 风格表格，可直接粘贴
- **零第三方依赖**：只用 `moonbitlang/core`，wasm / wasm-gc / js / native 四后端通吃

## 快速开始

```bash
# 运行内嵌示例（两组模拟推理基准数据的完整流程演示）
moon run cmd/main

# 跑测试（7 个行为测试）
moon test
```

示例输出（节选）：

```
== baseline vs tuned ==
| metric | baseline (avg) | tuned (avg) | delta |
|---|---:|---:|---:|
| ttft_p50_ms | 42.8 | 35.63 | -16.74% |
| tpot_ms | 13.93 | 11.63 | -16.51% |
| throughput_tok_s | 1214.9 | 1410.2 | +16.08% |
```

## 库 API 一览

```moonbit
// 解析长表 CSV
@benchlens.load_records(csv_text) -> Array[BenchRecord]
// 分组统计
@benchlens.aggregate(records) -> Array[MetricStats]   // n / avg / p50 / p99 / min / max
// 对比两个 run
@benchlens.compare(records, "baseline", "tuned") -> Array[MetricDiff]
// 渲染 Markdown 表
@benchlens.render_markdown_table(diffs, "baseline", "tuned") -> String
// 独立可复用的工具函数
@benchlens.parse_csv / mean / percentile / minimum / maximum / sorted_ascending
```

## 路线图

- [ ] CLI 参数化：`benchlens compare --base baseline --cand tuned results.csv`
- [ ] JSON 输入：直接解析 vLLM/SGLang `benchmark_serving` 的结果文件
- [ ] 多 run（>2）对比矩阵与最优 run 高亮
- [ ] 网页版（wasm 后端）：拖文件出报告，零安装
- [ ] 统计严谨性：小样本警告、离群值标注

## 参赛说明

本项目为 **2026 MoonBit 黑客松（11 月赛季）** 参赛作品，从零开始用 MoonBit 开发，开发过程在本仓库公开进行。

## License

Apache-2.0
