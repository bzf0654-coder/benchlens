///|
/// Demo run covering the whole pipeline:
/// 1) CSV long-format -> per-run statistics -> two-run Markdown comparison
/// 2) vLLM benchmark_serving-style JSON import -> statistics table with
///    small-sample flags -> multi-run comparison matrix
fn main {
  let sample = #|run,metric,value
                #|baseline,ttft_p50_ms,42.1
                #|baseline,ttft_p50_ms,44.8
                #|baseline,ttft_p50_ms,41.5
                #|baseline,tpot_ms,13.7
                #|baseline,tpot_ms,14.2
                #|baseline,tpot_ms,13.9
                #|baseline,throughput_tok_s,1240.5
                #|baseline,throughput_tok_s,1189.3
                #|tuned,ttft_p50_ms,35.2
                #|tuned,ttft_p50_ms,36.9
                #|tuned,ttft_p50_ms,34.8
                #|tuned,tpot_ms,11.6
                #|tuned,tpot_ms,11.9
                #|tuned,tpot_ms,11.4
                #|tuned,throughput_tok_s,1421.8
                #|tuned,throughput_tok_s,1398.6
  println("== [1] CSV long format ==")
  println(
    @lib.render_stats_table(@lib.aggregate(@lib.load_records(sample)),
    ),
  )
  println(@lib.render_markdown_table(
    @lib.compare(@lib.load_records(sample), "baseline", "tuned"),
    "baseline",
    "tuned",
  ))
  let base_json = #|{
                   #|  "backend": "vllm",
                   #|  "model": "qwen3",
                   #|  "mean_ttft_ms": 42.8,
                   #|  "mean_tpot_ms": 13.9,
                   #|  "request_throughput": 24.8,
                   #|  "ttfts": [40.1, 42.3, 45.9]
                   #|}
  let tuned_json = #|{
                    #|  "backend": "vllm",
                    #|  "model": "qwen3-int8",
                    #|  "mean_ttft_ms": 35.6,
                    #|  "mean_tpot_ms": 11.6,
                    #|  "request_throughput": 29.1,
                    #|  "ttfts": [34.2, 35.8, 36.7]
                    #|}
  println("== [2] vLLM benchmark_serving JSON ==")
  let all : Array[@lib.BenchRecord] = []
  for r in @lib.load_json_run(base_json, "fp16") {
    all.push(r)
  }
  for r in @lib.load_json_run(tuned_json, "int8") {
    all.push(r)
  }
  println(@lib.render_stats_table(@lib.aggregate(all)))
  println(@lib.render_run_matrix(all))
}
