// benchlens — parse, aggregate and compare LLM inference benchmark results.
//
// The library is intentionally dependency-free: everything is built on
// moonbitlang/core only, so the module builds for wasm, wasm-gc, js and
// native backends without any extra packages.

///|
// ---------- small string utilities ----------

/// Split a string by a single-character separator.
pub fn split_by(s : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for _, ch in s {
    if ch == sep {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(ch)
    }
  }
  out.push(buf.to_string())
  out
}

/// Split content into non-empty logical lines (handles \n and \r\n).
pub fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for _, ch in s {
    if ch == '\n' {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else if ch == '\r' {
      continue
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last != "" {
    out.push(last)
  }
  out
}

/// Trim spaces and tabs on both ends of a string.
pub fn trim(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && (s[start] == ' ' || s[start] == '\t') {
    start = start + 1
  }
  while end > start && (s[end - 1] == ' ' || s[end - 1] == '\t') {
    end = end - 1
  }
  s[start:end].to_owned()
}

///|
// ---------- CSV ----------

/// Minimal CSV parsing: split into lines, split fields on commas,
/// drop blank lines. Quoting is not handled (benchmark dumps rarely quote).
pub fn parse_csv(content : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  for line in split_lines(content) {
    let fields = split_by(line, ',')
    let meaningful = fields.length() > 1 || trim(fields[0]) != ""
    if meaningful {
      rows.push(fields)
    }
  }
  rows
}

///|
// ---------- statistics ----------

/// Parse a decimal number, returning None on failure.
pub fn to_double(s : String) -> Double? {
  try Some(@string.parse_double(trim(s))) catch {
    _ => None
  }
}

/// Arithmetic mean; aborts on empty input.
pub fn mean(values : Array[Double]) -> Double {
  if values.length() == 0 {
    abort("mean: empty input")
  }
  let mut sum = 0.0
  for v in values {
    sum = sum + v
  }
  sum / values.length().to_double()
}

/// Return a sorted copy of `values` in ascending order.
pub fn sorted_ascending(values : Array[Double]) -> Array[Double] {
  let out = values.copy()
  let n = out.length()
  for i in 1..<n {
    let mut j = i
    while j > 0 && out[j - 1] > out[j] {
      let tmp = out[j - 1]
      out[j - 1] = out[j]
      out[j] = tmp
      j = j - 1
    }
  }
  out
}

/// Linear-interpolated percentile of an unsorted sample; `p` in [0, 100].
pub fn percentile(values : Array[Double], p : Double) -> Double {
  if values.length() == 0 {
    abort("percentile: empty input")
  }
  let sorted = sorted_ascending(values)
  let n = sorted.length()
  if n == 1 {
    return sorted[0]
  }
  let rank = p / 100.0 * (n - 1).to_double()
  let lo = rank.floor().to_int()
  let hi = if lo + 1 < n { lo + 1 } else { lo }
  let frac = rank - lo.to_double()
  sorted[lo] * (1.0 - frac) + sorted[hi] * frac
}

/// Smallest value; aborts on empty input.
pub fn minimum(values : Array[Double]) -> Double {
  if values.length() == 0 {
    abort("minimum: empty input")
  }
  let mut m = values[0]
  let n = values.length()
  for i in 1..<n {
    if values[i] < m {
      m = values[i]
    }
  }
  m
}

/// Largest value; aborts on empty input.
pub fn maximum(values : Array[Double]) -> Double {
  if values.length() == 0 {
    abort("maximum: empty input")
  }
  let mut m = values[0]
  let n = values.length()
  for i in 1..<n {
    if values[i] > m {
      m = values[i]
    }
  }
  m
}

///|
// ---------- benchmark data model ----------

/// One benchmark measurement: `value` of `metric` observed in `run`.
#derive(Debug)
pub struct BenchRecord {
  run : String
  metric : String
  value : Double
}
pub extend BenchRecord with @debug.Debug::{to_repr}



/// Load records from CSV text with a `run,metric,value` header row.
/// Rows that are malformed or non-numeric are skipped.
pub fn load_records(content : String) -> Array[BenchRecord] {
  let records : Array[BenchRecord] = []
  let rows = parse_csv(content)
  for i, row in rows {
    if i == 0 {
      continue // header
    }
    if row.length() < 3 {
      continue
    }
    match to_double(row[2]) {
      Some(v) => records.push({ run: trim(row[0]), metric: trim(row[1]), value: v })
      None => continue
    }
  }
  records
}

/// Aggregated statistics of one metric within one run.
#derive(Debug)
pub struct MetricStats {
  run : String
  metric : String
  n : Int
  avg : Double
  p50 : Double
  p99 : Double
  lowest : Double
  highest : Double
}
pub extend MetricStats with @debug.Debug::{to_repr}



priv struct Group {
  run : String
  metric : String
  values : Array[Double]
}

/// Group records by (run, metric) and compute per-group statistics.
pub fn aggregate(records : Array[BenchRecord]) -> Array[MetricStats] {
  let groups : Array[Group] = []
  for record in records {
    let mut found : Group? = None
    for g in groups {
      if g.run == record.run && g.metric == record.metric {
        found = Some(g)
        break
      }
    }
    match found {
      Some(g) => g.values.push(record.value)
      None => {
        let values : Array[Double] = [record.value]
        groups.push({ run: record.run, metric: record.metric, values })
      }
    }
  }
  let out : Array[MetricStats] = []
  for g in groups {
    out.push(
      {
        run: g.run,
        metric: g.metric,
        n: g.values.length(),
        avg: mean(g.values),
        p50: percentile(g.values, 50.0),
        p99: percentile(g.values, 99.0),
        lowest: minimum(g.values),
        highest: maximum(g.values),
      },
    )
  }
  out
}

///|
// ---------- comparison ----------

/// Relative change from the base run to the candidate run, in percent.
#derive(Debug)
pub struct MetricDiff {
  metric : String
  base_avg : Double
  cand_avg : Double
  delta_pct : Double
}
pub extend MetricDiff with @debug.Debug::{to_repr}



fn filter_run(records : Array[BenchRecord], run : String) -> Array[BenchRecord] {
  let out : Array[BenchRecord] = []
  for r in records {
    if r.run == run {
      out.push(r)
    }
  }
  out
}

/// Compare two runs metric by metric, matching metrics by name.
/// Returns one MetricDiff per metric present in both runs.
pub fn compare(
  records : Array[BenchRecord],
  base_run : String,
  cand_run : String
) -> Array[MetricDiff] {
  let base_stats = aggregate(filter_run(records, base_run))
  let cand_stats = aggregate(filter_run(records, cand_run))
  let diffs : Array[MetricDiff] = []
  for b in base_stats {
    for c in cand_stats {
      if b.metric == c.metric {
        let delta = if b.avg == 0.0 {
          0.0
        } else {
          (c.avg - b.avg) / b.avg * 100.0
        }
        diffs.push(
          { metric: b.metric, base_avg: b.avg, cand_avg: c.avg, delta_pct: delta },
        )
      }
    }
  }
  diffs
}

///|
// ---------- rendering ----------

fn fmt_delta(pct : Double) -> String {
  if pct > 0.0 {
    "+" + pct.to_string() + "%"
  } else if pct < 0.0 {
    pct.to_string() + "%"
  } else {
    "0%"
  }
}

/// Render a comparison as a GitHub-flavoured Markdown table.
pub fn render_markdown_table(
  diffs : Array[MetricDiff],
  base_run : String,
  cand_run : String
) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "| metric | " + base_run + " (avg) | " + cand_run + " (avg) | delta |\n",
  )
  buf.write_string("|---|---:|---:|---:|\n")
  for d in diffs {
    buf.write_string(
      "| " + d.metric + " | " + d.base_avg.to_string() + " | " +
      d.cand_avg.to_string() + " | " + fmt_delta(d.delta_pct) + " |\n",
    )
  }
  buf.to_string()
}
