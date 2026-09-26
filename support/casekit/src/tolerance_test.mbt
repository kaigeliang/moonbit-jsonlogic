///|
test "numeric tolerance is opt in and does not coerce strings" {
  let a = @casekit.Suite::new("numbers")
  let b = @casekit.Suite::new("numbers")
  a.observe_number("sum", 0.3)
  b.observe_number("sum", 0.1 + 0.2)
  assert_false(@casekit.compare(a, b).is_match())
  assert_true(@casekit.compare(a, b, abs_tol=0.000000000001).is_match())
  a.observe("type", 1)
  b.observe("type", "1")
  assert_false(@casekit.compare(a, b, abs_tol=1.0).is_match())
}

///|
test "relative tolerance scales and invalid settings fail" {
  let a = @casekit.Suite::new("numbers")
  let b = @casekit.Suite::new("numbers")
  a.observe_number("large", 1000000.0)
  b.observe_number("large", 1000001.0)
  assert_true(@casekit.compare(a, b, rel_tol=0.000002).is_match())
  assert_false(@casekit.compare(a, b, rel_tol=0.0000001).is_match())
  assert_true(
    try {
      let _ = @casekit.compare(a, b, abs_tol=-1.0)
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      let _ = @casekit.compare(a, b, rel_tol=1.0 / 0.0)
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "relative comparisons avoid infinite subtraction shortcuts" {
  let a = @casekit.Suite::new("numbers")
  let b = @casekit.Suite::new("numbers")
  a.observe_number("huge", 1.0e308)
  b.observe_number("huge", -1.0e308)
  assert_false(@casekit.compare(a, b, rel_tol=0.01).is_match())
}
