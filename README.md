# benchlens

> A lens for LLM inference benchmarks —— 推理基准结果的"透镜"：一条流水线，把散落的 benchmark 数字变成可读、可对比、可粘贴的结论。

## 解决什么问题

做大模型推理优化（vLLM / SGLang / 国产算力适配）的人，每天都在产出基准数据：TTFT、TPOT、吞吐、延迟分位数……但两轮实验之间到底提升了多少，往往要靠手工翻日志、复制进 Excel 再手搓公式。数字散、口径乱、结论难复现。

benchlens 把这件事变成一条流水线：**读入 CSV 长表或 vLLM/SGLang 的 benchmark_serving JSON → 分组统计 → 多 run 对比 → 输出 Markdown 报告**，直接贴进 PR 描述或周报。

## 项目方向与通用性

本项目属于**开发者工具 / 数据处理**方向：输入是"带名字的数值序列"（长表 CSV 或 JSON 数值字段），核心是分组统计与对比，输出是 Markdown 报告。数据模型不绑定任何推理框架——任何"多次测量、按名分组、需要对比"的数据都能用：LLM 推理基准、CPU/编译器微基准、压测（RPS/延迟）、甚至硬件功耗采样。已知输入格式有两种（CSV 长表、benchmark_serving JSON），新增格式只需实现一个 `Array[BenchRecord]` 加载函数。

## 预期使用场景

1. **量化/调优回归对比**：对同一模型做优化前后各跑一轮 `benchmark_serving`，把两份 JSON 丢给 benchlens，得到 TTFT/TPOT/吞吐的均值、p50/p99 与相对变化表，直接贴进 PR——替代手工抄数和 Excel 公式。
2. **多硬件平台横评**：同一负载在 A100、DCU、昇腾等 N 块硬件上各产生一份结果，`render_run_matrix` 输出 N 列对比矩阵，每列带相对基准卡的 delta，缺失数据自动留空标记。
3. **CI 性能门禁**：把 benchlens 接入 CI，每个 PR 自动对比主线上一次基准，输出带 **小样本警告（n<30）** 的报告，防止 3 次采样波动被当成"性能提升"合入。

## 当前功能

- **CSV 解析（双格式自动识别）**：长表 `run,metric,value` 与宽表（表头即指标名，电子表格导出形态）自动分流，均跳过脏数据
- **JSON 导入**：手写递归下降 JSON 解析器（含转义、`\uXXXX` 与代理对）与对称的序列化器（可往返），直接读 vLLM/SGLang `benchmark_serving` 结果——顶层标量字段成为单样本指标，数值数组（`ttfts`/`itls`）成为逐请求样本，可算真实分位数
- **分组统计**：按 (run, metric) 分组计算 n / avg / p50 / p99 / min / max，n<30 自动标记小样本，IQR（Tukey 法）自动检测并标注离群样本
- **双 run 对比**：按指标名对齐，输出相对变化百分比
- **多 run 矩阵**：全部 run × 全部指标一张表，逐列带相对首个 run 的 delta，缺失格以 — 标记
- **定点数字格式化**：手写 `format_fixed`，报告里不再是 `42.800000000000004`
- **零第三方依赖**：只用 `moonbitlang/core`，wasm / wasm-gc / js / native 四后端通吃

## 快速开始

```bash
moon run cmd/main   # 完整演示：CSV 流程 + JSON 导入 + 多 run 矩阵
moon test           # 19 个行为测试
```

输出示例（节选）：

```
| metric | baseline (avg) | tuned (avg) | delta |
|---|---:|---:|---:|
| ttft_p50_ms | 42.80 | 35.63 | -16.7% |
| tpot_ms | 13.93 | 11.63 | -16.5% |
| throughput_tok_s | 1214.90 | 1410.20 | +16.1% |
```

## 库 API 一览

```moonbit
// 数据加载
@benchlens.load_records(csv) -> Array[BenchRecord]          // CSV 长表
@benchlens.load_json_run(json, "run-name") -> Array[BenchRecord]
@benchlens.json_parse(src) -> JsonValue                     // 通用 JSON 解析
@benchlens.json_get / json_as_double / json_as_string ...   // 类型安全访问器
// 统计
@benchlens.aggregate(records) -> Array[MetricStats]         // n/avg/p50/p99/min/max
@benchlens.percentile / mean / minimum / maximum / sorted_ascending
// 对比与渲染
@benchlens.compare(records, "base", "cand") -> Array[MetricDiff]
@benchlens.render_markdown_table(diffs, "base", "cand") -> String
@benchlens.render_run_matrix(records) -> String             // 多 run 矩阵
@benchlens.render_stats_table(stats) -> String              // 统计表 + 小样本标记
@benchlens.format_fixed(value, digits) -> String
```

## 路线图

- [x] JSON 输入：直接解析 vLLM/SGLang `benchmark_serving` 的结果文件
- [x] 多 run（>2）对比矩阵
- [x] 统计严谨性：小样本警告（n<30 标记）
- [ ] CLI 参数化：`benchlens compare --base baseline --cand tuned results.csv`
- [ ] 网页版（wasm 后端）：拖文件出报告，零安装
- [x] 离群值标注（IQR / Tukey fences）

## 参赛声明

- 本项目为 **2026 MoonBit 黑客松（11 月赛季）** 参赛作品
- **原创项目**：从空白工程开始开发，非移植项目，未参考或复用任何已有开源项目的实现；MoonBit 标准库（moonbitlang/core）之外零依赖
- 开发过程在本仓库公开进行，每个 commit 对应一个完整功能（含测试）

## License

Apache-2.0
