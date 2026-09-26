///|
test "nested differences identify exact JSON pointers" {
  let a = @casekit.Suite::new("s")
  let b = @casekit.Suite::new("s")
  a.observe("tree", { "a/b~c": [{ "value": 1, "gone": null }] })
  b.observe("tree", { "a/b~c": [{ "value": "1", "new": true }] })
  let ds = @casekit.compare(a, b).differences
  assert_eq(ds.length(), 3)
  assert_eq(ds[0].path, "/a~1b~0c/0/gone")
  assert_true(ds[0].kind == @casekit.MissingField)
  assert_eq(ds[1].path, "/a~1b~0c/0/new")
  assert_eq(ds[2].path, "/a~1b~0c/0/value")
  assert_true(ds[2].kind == @casekit.TypeMismatch)
}

///|
test "array truncation is not equivalent to a null entry" {
  let a = @casekit.Suite::new("s")
  let b = @casekit.Suite::new("s")
  a.observe("array", [1, null])
  b.observe("array", [1])
  let ds = @casekit.compare(a, b).differences
  assert_eq(ds.length(), 1)
  assert_eq(ds[0].path, "/1")
  assert_true(ds[0].kind == @casekit.MissingField)
}
