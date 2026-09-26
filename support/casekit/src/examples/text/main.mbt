///|
fn main raise {
  let s = @casekit.Suite::new("unicode-and-json")
  let text = "你好🌙"
  s.observe(
    "unicode/codepoints",
    text.iter().map(c => c.to_int()).to_array().to_json(),
  )
  s.observe("unicode/length", {
    "utf16_units": text.length().to_json(),
    "characters": text.to_array().length().to_json(),
  })
  let source = "{\"message\":\"line\\nquote\\\"\",\"items\":[true,null,3]}"
  s.observe("json/roundtrip", @json.parse(source))
  println(s.encode())
}
