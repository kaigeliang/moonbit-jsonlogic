///|
test "transcript round trip preserves value kinds" {
  let s = @casekit.Suite::new("roundtrip")
  s.observe("nested", { "null": null, "bool": false, "arr": ["x", 2] })
  assert_eq(@casekit.decode(s.encode()).encode(), s.encode())
}

///|
test "malformed transcripts never become passing empty suites" {
  let bad = [
    "", "{", "[]", "{\"casekit\":2,\"suite\":\"s\",\"cases\":[{\"id\":\"a\",\"value\":1}]}",
    "{\"casekit\":1,\"suite\":\"s\",\"cases\":[]}", "{\"casekit\":1,\"suite\":\"s\",\"cases\":[{\"id\":\"a\",\"value\":1},{\"id\":\"a\",\"value\":2}]}",
    "{\"casekit\":1,\"suite\":\"s\",\"cases\":[{\"id\":\"a\"}]}", "{\"casekit\":1,\"suite\":\"s\",\"cases\":[{\"id\":\"a\",\"value\":1}],\"extra\":0}",
  ]
  for source in bad {
    assert_true(
      try {
        let _ = @casekit.decode(source)
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}
