///|
test "large integer lexemes cannot collapse to equal doubles" {
  let prefix = "{\"casekit\":1,\"suite\":\"large\",\"cases\":[{\"id\":\"value\",\"value\":{\"nested\":["
  let suffix = "]}}]}"
  let a = @casekit.decode(prefix + "9007199254740992" + suffix)
  let b = @casekit.decode(prefix + "9007199254740993" + suffix)
  let report = @casekit.compare(a, b)
  assert_false(report.is_match())
  assert_eq(report.differences[0].path, "/nested/0")
}

///|
test "equivalent ordinary number spellings and negative zero agree" {
  let a = @casekit.Suite::new("n")
  let b = @casekit.Suite::new("n")
  a.observe_number("one", 1.0)
  b.observe("one", 1)
  a.observe_number("zero", -0.0)
  b.observe_number("zero", 0.0)
  assert_true(@casekit.compare(a, b).is_match())
}
