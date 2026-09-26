///|
test "case order and object key order do not change behavior" {
  let a = @casekit.Suite::new("s")
  let b = @casekit.Suite::new("s")
  a.observe("a", { "x": 1, "y": 2 })
  a.observe("b", [1, 2])
  b.observe("b", [1, 2])
  b.observe("a", { "y": 2, "x": 1 })
  let report = @casekit.compare(a, b)
  assert_true(report.is_match())
  assert_eq(report.matched_cases, 2)
}

///|
test "missing extra and changed observations remain distinct" {
  let a = @casekit.Suite::new("s")
  let b = @casekit.Suite::new("s")
  a.observe("missing", null)
  a.observe("changed", [1, 2])
  b.observe("extra", null)
  b.observe("changed", [2, 1])
  let report = @casekit.compare(a, b)
  assert_false(report.is_match())
  assert_eq(report.total_cases, 3)
  assert_eq(report.differences[0].case_id, "changed")
  assert_true(report.differences[2].kind == @casekit.ExtraCase)
  assert_true(report.differences[3].kind == @casekit.MissingCase)
}

///|
test "different suites cannot accidentally pass" {
  let a = @casekit.Suite::new("left")
  let b = @casekit.Suite::new("right")
  a.observe("case", 1)
  b.observe("case", 1)
  assert_true(
    try {
      let _ = @casekit.compare(a, b)
      false
    } catch {
      Invalid(_) => true
    },
  )
}
