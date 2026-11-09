// Blackbox tests for the JSON value model and parser.

///|
test "json_parse handles scalars" {
  inspect(@benchlens.json_parse("null").to_repr(), content="JNull")
  inspect(@benchlens.json_parse("true").to_repr(), content="JBool(true)")
  inspect(@benchlens.json_parse("false").to_repr(), content="JBool(false)")
  inspect(@benchlens.json_parse("42").to_repr(), content="JNumber(42)")
  inspect(@benchlens.json_parse("-3.5").to_repr(), content="JNumber(-3.5)")
  inspect(
    @benchlens.json_parse("1.25e3").to_repr(),
    content="JNumber(1250)",
  )
  inspect(@benchlens.json_parse("\"hello\"").to_repr(), content="JString(\"hello\")")
}

///|
test "json_parse skips whitespace around the document" {
  inspect(@benchlens.json_parse("  7  ").to_repr(), content="JNumber(7)")
}
