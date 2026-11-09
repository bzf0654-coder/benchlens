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

///|
test "json_parse handles string escapes" {
  inspect(@benchlens.json_parse("\"a\\nb\"").to_repr(), content=(
    #|JString("a\nb")
  ))
  inspect(@benchlens.json_parse("\"tab\\there\"").to_repr(), content=(
    #|JString("tab\there")
  ))
  inspect(@benchlens.json_parse("\"quote\\\"slash\\\\\"").to_repr(), content=(
    #|JString("quote\"slash\\")
  ))
  inspect(@benchlens.json_parse("\"\\u4e2d\\u6587\"").to_repr(), content=(
    #|JString("中文")
  ))
  inspect(@benchlens.json_parse("\"\\ud83d\\ude00\"").to_repr(), content=(
    #|JString("😀")
  ))
}

///|
test "json_parse handles arrays and objects with nesting" {
  let doc = "{\"backend\":\"vllm\",\"median_ttft_ms\":12.5,\"ttfts\":[1.0, 2.0, 3.0],\"meta\":{\"shape\":{\"a\":1},\"flags\":[true, false, null]},\"empty_obj\":{},\"empty_arr\":[]}"
  let repr = @debug.to_string(@benchlens.json_parse(doc))
  inspect(repr.contains("JObject"), content="true")
  inspect(repr.contains("JString(\"vllm\")"), content="true")
  inspect(repr.contains("JNumber(12.5)"), content="true")
  inspect(repr.contains("JNumber(1)"), content="true")
  inspect(repr.contains("JBool(true)"), content="true")
  inspect(repr.contains("JNull"), content="true")
  inspect(@benchlens.json_parse("[]").to_repr(), content="JArray([])")
  inspect(@benchlens.json_parse("{}").to_repr(), content="JObject([])")
}
