///|
test "collect case identity and reject duplicates" {
  let s = @casekit.Suite::new("unicode")
  s.observe("text", "你好🌙")
  assert_eq(s.size(), 1)
  let duplicate = try {
    s.observe("text", "other")
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(duplicate)
  assert_true(s.encode().contains("你好"))
}

///|
test "empty and non finite observations fail explicitly" {
  assert_true(
    try {
      let _ = @casekit.Suite::new(" ")
      false
    } catch {
      Invalid(_) => true
    },
  )
  let s = @casekit.Suite::new("numbers")
  assert_true(
    try {
      let _ = s.encode()
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      s.observe_number("nan", 0.0 / 0.0)
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(s.size(), 0)
}
