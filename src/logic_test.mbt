///|
test "business rule preserves result values and input data" {
  let data : Json = { "age": 20, "active": true }
  let rule : Json = {
    "and": [{ ">=": [{ "var": "age" }, 18] }, { "var": "active" }],
  }
  assert_eq(@jsonlogic.apply(rule, data), true)
  assert_eq(data, { "age": 20, "active": true })
}

///|
test "logs capture only evaluated branches" {
  let result = @jsonlogic.evaluate(
    { "if": [true, { "log": 7 }, { "log": 9 }] },
    {},
  )
  assert_eq(result.value, 7)
  assert_eq(result.logs, [7])
  assert_true(result.steps_used > 0)
}

///|
test "unknown operator reports the nested rule location" {
  try {
    let _ = @jsonlogic.apply({ "map": [[1], { "bad/op~": [] }] }, {})
    fail("expected invalid rule")
  } catch {
    @jsonlogic.InvalidRule(path, _) => assert_eq(path, "/map/1")
    _ => fail("wrong error")
  }
}

///|
test "execution limits stop work even inside collection operations" {
  try {
    let _ = @jsonlogic.evaluate(
      { "map": [[1, 2, 3, 4], { "+": [{ "var": "" }, 1] }] },
      {},
      max_steps=20,
    )
    fail("expected budget failure")
  } catch {
    @jsonlogic.LimitExceeded(_) => ()
    _ => fail("wrong error")
  }
}

///|
test "depth limit rejects deeply nested inputs before evaluation" {
  try {
    let _ = @jsonlogic.evaluate(1, [[[1]]], max_depth=2)
    fail("expected depth failure")
  } catch {
    @jsonlogic.LimitExceeded(_) => ()
    _ => fail("wrong error")
  }
}

///|
test "non-finite arithmetic is an error rather than JSON null" {
  for
    rule in ([{ "/": [1, 0] }, { "+": ["abc", 2] }, { "min": [] }] : Array[Json]) {
    try {
      let _ = @jsonlogic.apply(rule, {})
      fail("expected numeric failure")
    } catch {
      @jsonlogic.NonFiniteNumber(_) => ()
      _ => fail("wrong error")
    }
  }
}

///|
test "invalid JSON reports parse errors separately" {
  try {
    let _ = @jsonlogic.apply_json("{", "{}")
    fail("expected invalid input")
  } catch {
    @jsonlogic.InvalidInput(message) => assert_eq(message, "invalid rule JSON")
    _ => fail("wrong error")
  }
}

///|
test "undefined and malformed arity are explicit failures" {
  for
    rule in (
      [{ "and": [] }, { "/": [1] }, { "missing_some": [1, "x"] }] : Array[Json]) {
    try {
      let _ = @jsonlogic.apply(rule, {})
      fail("expected invalid rule")
    } catch {
      @jsonlogic.InvalidRule(_, _) => ()
      _ => fail("wrong error")
    }
  }
}

///|
test "var accesses JSON own keys without JavaScript prototypes" {
  assert_eq(
    @jsonlogic.apply({ "var": ["constructor", "missing"] }, {}),
    "missing",
  )
  assert_eq(@jsonlogic.apply({ "var": "__proto__" }, { "__proto__": 7 }), 7)
}

///|
test "missing treats null and empty string as missing but preserves false and zero" {
  assert_eq(
    @jsonlogic.apply({ "missing": ["a", "b", "c", "d", "e"] }, {
      "a": null,
      "b": "",
      "c": false,
      "d": 0,
    }),
    ["a", "b", "e"],
  )
}

///|
test "each invocation has a fresh budget and log collection" {
  let first = @jsonlogic.evaluate({ "log": 1 }, {})
  let second = @jsonlogic.evaluate(2, {})
  assert_eq(first.logs, [1])
  assert_eq(second.logs, [])
}

///|
test "limit configuration is validated" {
  try {
    let _ = @jsonlogic.evaluate(1, {}, max_steps=0)
    fail("expected invalid input")
  } catch {
    @jsonlogic.InvalidInput(_) => ()
    _ => fail("wrong error")
  }
}

///|
test "shorthand arguments keep their real JSON Pointer" {
  try {
    let _ = @jsonlogic.apply({ "!": { "unknown": [] } }, {})
    fail("expected invalid rule")
  } catch {
    @jsonlogic.InvalidRule(path, _) => assert_eq(path, "/!")
    _ => fail("wrong error")
  }
}

///|
test "substring and indexed lookup cannot silently lose half a surrogate pair" {
  for
    rule in ([{ "substr": ["🌙", 0, 1] }, { "var": "text.0" }] : Array[Json]) {
    try {
      let _ = @jsonlogic.apply(rule, { "text": "🌙" })
      fail("expected invalid Unicode result")
    } catch {
      @jsonlogic.InvalidRule(_, message) =>
        assert_eq(message, "operation produces an unpaired UTF-16 surrogate")
      _ => fail("wrong error")
    }
  }
}
