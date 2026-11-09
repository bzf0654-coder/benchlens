///|
/// Demo run: aggregate an embedded two-run sample and print a Markdown
/// comparison report. Real file/stdin input lands with the CLI layer
/// (see README roadmap).
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
  let records = @lib.load_records(sample)
  println("== per-run statistics ==")
  for s in @lib.aggregate(records) {
    println(s.to_repr())
  }
  println("")
  println("== baseline vs tuned ==")
  println(
    @lib.render_markdown_table(
      @lib.compare(records, "baseline", "tuned"),
      "baseline",
      "tuned",
    ),
  )
}
