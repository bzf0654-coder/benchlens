// A hand-written JSON value model and recursive-descent parser.
// Benchmarks are reported as JSON by vLLM/SGLang tooling, so benchlens can
// consume those files directly instead of requiring CSV exports.
//
// Limitation: the parser walks the source by char index, which is exact for
// ASCII and BMP content — benchmark payloads in practice.

#derive(Debug)
pub enum JsonValue {
  JNull
  JBool(Bool)
  JNumber(Double)
  JString(String)
  JArray(Array[JsonValue])
  JObject(Array[(String, JsonValue)])
}

pub extend JsonValue with @debug.Debug::{to_repr}

///|
// ---------- parser state ----------

priv struct JsonParser {
  src : String
  mut pos : Int
}

fn peek(p : JsonParser) -> Char {
  match p.src.get_char(p.pos) {
    Some(c) => c
    None => '\u{0}'
  }
}

fn advance(p : JsonParser) -> Char {
  let ch = peek(p)
  if ch != '\u{0}' {
    p.pos = p.pos + 1
  }
  ch
}

fn skip_ws(p : JsonParser) -> Unit {
  let mut ch = peek(p)
  while ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
    p.pos = p.pos + 1
    ch = peek(p)
  }
}

fn expect(p : JsonParser, want : Char) -> Unit {
  let got = advance(p)
  if got != want {
    abort("json: expected '\{want}' at offset \{p.pos - 1}, got '\{got}'")
  }
}

///|
// ---------- scalars ----------

fn parse_null(p : JsonParser) -> JsonValue {
  expect(p, 'n')
  expect(p, 'u')
  expect(p, 'l')
  expect(p, 'l')
  JNull
}

fn parse_true(p : JsonParser) -> JsonValue {
  expect(p, 't')
  expect(p, 'r')
  expect(p, 'u')
  expect(p, 'e')
  JBool(true)
}

fn parse_false(p : JsonParser) -> JsonValue {
  expect(p, 'f')
  expect(p, 'a')
  expect(p, 'l')
  expect(p, 's')
  expect(p, 'e')
  JBool(false)
}

fn parse_number(p : JsonParser) -> JsonValue {
  let buf = StringBuilder()
  let mut ch = peek(p)
  if ch == '-' {
    buf.write_char(advance(p))
    ch = peek(p)
  }
  while ch >= '0' && ch <= '9' {
    buf.write_char(advance(p))
    ch = peek(p)
  }
  if ch == '.' {
    buf.write_char(advance(p))
    ch = peek(p)
    while ch >= '0' && ch <= '9' {
      buf.write_char(advance(p))
      ch = peek(p)
    }
  }
  if ch == 'e' || ch == 'E' {
    buf.write_char(advance(p))
    ch = peek(p)
    if ch == '+' || ch == '-' {
      buf.write_char(advance(p))
    }
    ch = peek(p)
    while ch >= '0' && ch <= '9' {
      buf.write_char(advance(p))
      ch = peek(p)
    }
  }
  let parsed : Double? = try Some(@string.parse_double(buf.to_string())) catch {
    _ => None
  }
  match parsed {
    Some(v) => JNumber(v)
    None => abort("json: invalid number at offset \{p.pos}")
  }
}

fn hex_value(ch : Char) -> Int? {
  if !ch.is_ascii_hexdigit() {
    return None
  }
  let d = ch.to_int()
  if ch >= '0' && ch <= '9' {
    Some(d - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(d - 'a'.to_int() + 10)
  } else {
    Some(d - 'A'.to_int() + 10)
  }
}

fn parse_hex4(p : JsonParser) -> Int {
  let mut value = 0
  for _ in 0..<4 {
    let ch = advance(p)
    match hex_value(ch) {
      Some(d) => value = value * 16 + d
      None => abort("json: invalid \\u escape at offset \{p.pos - 1}")
    }
  }
  value
}

fn write_codepoint(buf : StringBuilder, code : Int) -> Unit {
  match code.to_char() {
    Some(c) => buf.write_char(c)
    None => abort("json: invalid unicode codepoint \{code}")
  }
}

fn parse_string_raw(p : JsonParser) -> String {
  expect(p, '"')
  let buf = StringBuilder()
  let mut ch = advance(p)
  while ch != '"' {
    if ch == '\u{0}' {
      abort("json: unterminated string")
    }
    if ch == '\\' {
      let esc = advance(p)
      match esc {
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/')
        'b' => write_codepoint(buf, 8)
        'f' => write_codepoint(buf, 12)
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'u' => {
          let hi = parse_hex4(p)
          if hi >= 0xD800 && hi <= 0xDBFF {
            expect(p, '\\')
            expect(p, 'u')
            let lo = parse_hex4(p)
            if lo >= 0xDC00 && lo <= 0xDFFF {
              let code = 0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)
              write_codepoint(buf, code)
            } else {
              abort("json: unpaired high surrogate at offset \{p.pos}")
            }
          } else if hi >= 0xDC00 && hi <= 0xDFFF {
            abort("json: unpaired low surrogate at offset \{p.pos}")
          } else {
            write_codepoint(buf, hi)
          }
        }
        other => abort("json: invalid escape '\\\{other}' at offset \{p.pos}")
      }
    } else {
      buf.write_char(ch)
    }
    ch = advance(p)
  }
  buf.to_string()
}

///|
// ---------- containers ----------

fn parse_array(p : JsonParser) -> JsonValue {
  expect(p, '[')
  skip_ws(p)
  let items : Array[JsonValue] = []
  if peek(p) == ']' {
    ignore(advance(p))
    return JArray(items)
  }
  while true {
    items.push(parse_value(p))
    skip_ws(p)
    match advance(p) {
      ',' => continue
      ']' => break
      other => abort(
        "json: expected ',' or ']' at offset \{p.pos - 1}, got '\{other}'",
      )
    }
  }
  JArray(items)
}

fn parse_object(p : JsonParser) -> JsonValue {
  expect(p, '{')
  skip_ws(p)
  let fields : Array[(String, JsonValue)] = []
  if peek(p) == '}' {
    ignore(advance(p))
    return JObject(fields)
  }
  while true {
    skip_ws(p)
    let key = parse_string_raw(p)
    skip_ws(p)
    expect(p, ':')
    let value = parse_value(p)
    fields.push((key, value))
    skip_ws(p)
    match advance(p) {
      ',' => continue
      '}' => break
      other => abort(
        "json: expected ',' or '}' at offset \{p.pos - 1}, got '\{other}'",
      )
    }
  }
  JObject(fields)
}

///|
// ---------- entry point ----------

/// Parse a JSON document into a `JsonValue`.
/// The full grammar is supported: objects, arrays (nested to any depth),
/// strings with escapes, numbers, booleans and null.
pub fn json_parse(src : String) -> JsonValue {
  let p = { src, pos: 0 }
  let value = parse_value(p)
  skip_ws(p)
  if peek(p) != '\u{0}' {
    abort("json: trailing garbage at offset \{p.pos}")
  }
  value
}

fn parse_value(p : JsonParser) -> JsonValue {
  skip_ws(p)
  match peek(p) {
    'n' => parse_null(p)
    't' => parse_true(p)
    'f' => parse_false(p)
    '"' => JString(parse_string_raw(p))
    '[' => parse_array(p)
    '{' => parse_object(p)
    '-' => parse_number(p)
    c => {
      if c >= '0' && c <= '9' {
        parse_number(p)
      } else {
        abort("json: unexpected character '\{c}' at offset \{p.pos}")
      }
    }
  }
}
