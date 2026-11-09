// Blackbox tests for the public API of @benchlens.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "parse_csv splits lines and fields, drops blanks" {
  let rows = @benchlens.parse_csv("run,metric,value\n\nbaseline,tps,100\r\n")
  inspect(rows.length(), content="2")
  inspect(rows[0].length(), content="3")
  inspect(rows[1][2], content="100")
}

///|
test "trim removes surrounding spaces and tabs" {
  inspect(@benchlens.trim("  x "), content="x")
  inspect(@benchlens.trim("\ty\t"), content="y")
  inspect(@benchlens.trim("no-space"), content="no-space")
}

///|
test "mean and percentile basics" {
  inspect(@benchlens.mean([1.0, 2.0, 3.0]), content="2")
  inspect(@benchlens.percentile([10.0, 20.0, 30.0, 40.0], 50.0), content="25")
  inspect(@benchlens.percentile([5.0], 99.0), content="5")
  inspect(@benchlens.minimum([3.0, 1.0, 2.0]), content="1")
  inspect(@benchlens.maximum([3.0, 1.0, 2.0]), content="3")
}

///|
test "load_records skips header and malformed rows" {
  let csv = "run,metric,value\nold,tps,100\nbad-row\nold,tps,not-a-number\nold,tps,200\n"
  let records = @benchlens.load_records(csv)
  inspect(records.length(), content="2")
  inspect(records[0].run, content="old")
  inspect(records[1].value.to_string(), content="200")
}

///|
test "aggregate computes group statistics" {
  let csv = "run,metric,value\nold,tps,100\nold,tps,200\nold,tps,300\n"
  let stats = @benchlens.aggregate(@benchlens.load_records(csv))
  inspect(stats.length(), content="1")
  inspect(stats[0].n, content="3")
  inspect(stats[0].avg, content="200")
  inspect(stats[0].p50, content="200")
}

///|
test "compare computes relative delta between two runs" {
  let csv = "run,metric,value\nold,tps,100\nold,tps,200\nnew,tps,300\nnew,tps,500\n"
  let diffs = @benchlens.compare(@benchlens.load_records(csv), "old", "new")
  inspect(diffs.length(), content="1")
  inspect(diffs[0].base_avg, content="150")
  inspect(diffs[0].cand_avg, content="400")
  inspect(diffs[0].delta_pct, content=(
    #|166.66666666666669
  ))
}

///|
test "render_markdown_table produces a table" {
  let csv = "run,metric,value\nold,tps,100\nnew,tps,200\n"
  let diffs = @benchlens.compare(@benchlens.load_records(csv), "old", "new")
  let table = @benchlens.render_markdown_table(diffs, "old", "new")
  inspect(table.contains("| metric |"), content="true")
  inspect(table.contains("tps"), content="true")
  inspect(table.contains("+100"), content="true")
}

///|
test "load_json_run extracts scalars and numeric arrays" {
  let doc = "{\"backend\":\"vllm\",\"mean_ttft_ms\":42.0,\"request_throughput\":12.5,\"ttfts\":[10.0,20.0,60.0],\"labels\":[\"a\",\"b\"],\"ok\":true,\"empty\":[]}"
  let records = @benchlens.load_json_run(doc, "vllm-a100")
  inspect(records.length(), content="5")
  let stats = @benchlens.aggregate(records)
  inspect(stats.length(), content="3")
  let mut found = false
  for s in stats {
    if s.metric == "ttfts" {
      found = true
      inspect(s.n, content="3")
      inspect(s.avg, content="30")
      inspect(s.p50, content="20")
    }
  }
  inspect(found, content="true")
}
