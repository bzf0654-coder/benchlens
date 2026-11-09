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
    "+" + format_fixed(pct, 1) + "%"
  } else if pct < 0.0 {
    format_fixed(pct, 1) + "%"
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
      "| " + d.metric + " | " + format_fixed(d.base_avg, 2) + " | " +
      format_fixed(d.cand_avg, 2) + " | " + fmt_delta(d.delta_pct) + " |\n",
    )
  }
  buf.to_string()
}

///|
// ---------- JSON benchmark loading ----------

/// Load a benchmark_serving-style JSON report (vLLM/SGLang) as records
/// under the given run name. Top-level numeric fields become single-sample
/// metrics; top-level arrays of numbers become per-sample metrics
/// (e.g. "ttfts" / "itls"), so percentiles can be computed from raw data.
/// Strings, booleans and mixed arrays are ignored.
pub fn load_json_run(content : String, run : String) -> Array[BenchRecord] {
  let records : Array[BenchRecord] = []
  match json_parse(content) {
    JObject(fields) =>
      for field in fields {
        let key = field.0
        match field.1 {
          JNumber(x) => records.push({ run, metric: key, value: x })
          JArray(items) => {
            let mut numeric = items.length() > 0
            for item in items {
              match item {
                JNumber(_) => continue
                _ => {
                  numeric = false
                  break
                }
              }
            }
            if numeric {
              for item in items {
                match item {
                  JNumber(x) => records.push({ run, metric: key, value: x })
                  _ => ()
                }
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  records
}

///|
// ---------- multi-run matrix ----------

fn contains_str(arr : Array[String], x : String) -> Bool {
  for item in arr {
    if item == x {
      return true
    }
  }
  false
}

fn avg_lookup(
  stats : Array[MetricStats],
  run : String,
  metric : String
) -> Double? {
  for s in stats {
    if s.run == run && s.metric == metric {
      return Some(s.avg)
    }
  }
  None
}

/// Render every run x metric as a Markdown matrix.
/// Columns are runs in first-seen order; every run after the first also
/// shows a delta percentage relative to the first run. Cells for metrics
/// missing in a run render as an em dash.
pub fn render_run_matrix(records : Array[BenchRecord]) -> String {
  let stats = aggregate(records)
  let runs : Array[String] = []
  for s in stats {
    if !contains_str(runs, s.run) {
      runs.push(s.run)
    }
  }
  let metrics : Array[String] = []
  for s in stats {
    if !contains_str(metrics, s.metric) {
      metrics.push(s.metric)
    }
  }
  let buf = StringBuilder()
  buf.write_string("| metric |")
  for r in runs {
    buf.write_string(" " + r + " |")
  }
  buf.write_string("\n|---|")
  for _ in runs {
    buf.write_string("---:|")
  }
  buf.write_string("\n")
  for m in metrics {
    buf.write_string("| " + m + " |")
    let base = avg_lookup(stats, runs[0], m)
    for i, r in runs {
      match avg_lookup(stats, r, m) {
        Some(v) => {
          let cell = format_fixed(v, 2)
          match (i, base) {
            (0, _) => buf.write_string(" " + cell + " |")
            (_, Some(b)) => {
              let d = if b == 0.0 {
                0.0
              } else {
                (v - b) / b * 100.0
              }
              buf.write_string(" " + cell + " (" + fmt_delta(d) + ") |")
            }
            (_, None) => buf.write_string(" " + cell + " |")
          }
        }
        None => buf.write_string(" — |")
      }
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
// ---------- per-run statistics table ----------

/// Render aggregated statistics as a Markdown table.
/// Groups with fewer than 30 samples are flagged so that small-sample
/// conclusions are visible at a glance.
pub fn render_stats_table(stats : Array[MetricStats]) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "| run | metric | n | avg | p50 | p99 | min | max | note |\n",
  )
  buf.write_string("|---|---|---:|---:|---:|---:|---:|---:|---|\n")
  for s in stats {
    let note = if s.n < 30 {
      "small sample (n<30)"
    } else {
      ""
    }
    buf.write_string(
      "| " + s.run + " | " + s.metric + " | " + s.n.to_string() + " | " +
      format_fixed(s.avg, 2) + " | " + format_fixed(s.p50, 2) + " | " +
      format_fixed(s.p99, 2) + " | " + format_fixed(s.lowest, 2) + " | " +
      format_fixed(s.highest, 2) + " | " + note + " |\n",
    )
  }
  buf.to_string()
}

///|
// ---------- number formatting ----------

fn pow10(n : Int) -> Double {
  let mut r = 1.0
  for _ in 0..<n {
    r = r * 10.0
  }
  r
}

/// Format a double with a fixed number of digits after the decimal point,
/// rounding half away from zero. Hand-rolled so the library stays free of
/// any dependency beyond moonbitlang/core.
pub fn format_fixed(value : Double, digits : Int) -> String {
  let neg = value < 0.0
  let abs = if neg { -value } else { value }
  let scale = pow10(digits)
  let scaled = (abs * scale + 0.5).floor()
  let int_part = (scaled / scale).floor().to_int()
  let frac_part = (scaled - int_part.to_double() * scale).to_int()
  let frac_str = frac_part.to_string()
  let mut padded = frac_str
  while padded.length() < digits {
    padded = "0" + padded
  }
  let mut out = int_part.to_string()
  if digits > 0 {
    out = out + "." + padded
  }
  if neg {
    "-" + out
  } else {
    out
  }
}
