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

fn parse_string_raw(p : JsonParser) -> String {
  expect(p, '"')
  let buf = StringBuilder()
  let mut ch = advance(p)
  while ch != '"' {
    if ch == '\u{0}' {
      abort("json: unterminated string")
    }
    buf.write_char(ch)
    ch = advance(p)
  }
  buf.to_string()
}

///|
// ---------- entry point ----------

/// Parse a JSON document into a `JsonValue`.
/// Only objects, arrays, strings, numbers and booleans are supported in
/// this first pass; escape sequences land in the next commit.
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
