///|
test "reports preserve missing versus null and limit presentation only" {
  let a = @casekit.Suite::new("s")
  let b = @casekit.Suite::new("s")
  a.observe("a", { "key": null })
  b.observe("a", {})
  a.observe("b", "first\nline")
  b.observe("b", "second\nline")
  let report = @casekit.compare(a, b)
  let text = report.render(max_differences=1)
  assert_true(text.contains("expected: null"))
  assert_true(text.contains("actual:   <missing>"))
  assert_true(text.contains("1 more differences"))
  assert_eq(report.differences.length(), 2)
  assert_true(report.encode().contains("MissingField"))
}

///|
test "diagnostics escape user supplied line breaks" {
  let a = @casekit.Suite::new("line\nbreak")
  let b = @casekit.Suite::new("line\nbreak")
  a.observe("case\nid", "a\nb")
  b.observe("case\nid", "x")
  let lines = @casekit.compare(a, b).render().split("\n").to_array()
  assert_eq(lines.length(), 4)
}
