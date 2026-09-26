///|
test "objects sort recursively while arrays retain order" {
  assert_eq(
    @casekit.canonical({ "z": [2, 1], "a": { "y": true, "b": null } }),
    "{\"a\":{\"b\":null,\"y\":true},\"z\":[2,1]}",
  )
}

///|
test "observations are snapshots and suite ordering is stable" {
  let a = @casekit.Suite::new("values")
  let values : Array[Json] = [1, 2]
  a.observe("z", values.to_json())
  values[0] = 99
  a.observe("a", true)
  let b = @casekit.Suite::new("values")
  b.observe("a", true)
  b.observe("z", [1, 2])
  assert_eq(a.encode(), b.encode())
}
