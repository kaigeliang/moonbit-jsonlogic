///|
fn fields() -> Array[@queryx.Field] {
  [
    { name: "age", kind: @queryx.FieldType::Number, },
    { name: "status", kind: @queryx.FieldType::String, },
    { name: "active", kind: @queryx.FieldType::Bool, },
  ]
}

///|
fn expect_rule_error(rule : Json, expected_path : String) -> Unit raise {
  try {
    let _ = @queryx.import_filter(rule, fields())
    fail("expected the unsupported filter to be rejected")
  } catch {
    @queryx.InvalidRule(path, _) => assert_eq(path, expected_path)
    error => fail("unexpected error: " + error.to_string())
  }
}

///|
test "numeric comparisons and reversed operands preserve direction" {
  let expr = @queryx.import_filter({ ">=": [{ "var": "age" }, 18] }, fields())
  assert_eq(expr, @qx.Expr::Compare("age", @qx.CmpOp::Ge, @qx.Value::Int(18L)))
  let reversed = @queryx.import_filter(
    { "<": [18, { "var": ["age"] }] },
    fields(),
  )
  assert_eq(
    reversed,
    @qx.Expr::Compare("age", @qx.CmpOp::Gt, @qx.Value::Int(18L)),
  )
  assert_false(reversed.eval(Map([("age", @qx.Value::Int(18L))])))
  assert_true(reversed.eval(Map([("age", @qx.Value::Int(19L))])))
}

///|
test "open ranges keep both strict endpoints without a JSON roundtrip" {
  let expr = @queryx.import_filter(
    {
      "and": [{ ">": [{ "var": "age" }, 18] }, { "<": [{ "var": "age" }, 65] }],
    },
    fields(),
  )
  assert_eq(
    expr,
    @qx.Expr::And([
      @qx.Expr::Compare("age", @qx.CmpOp::Gt, @qx.Value::Int(18L)),
      @qx.Expr::Compare("age", @qx.CmpOp::Lt, @qx.Value::Int(65L)),
    ]),
  )
  for age in [18L, 65L] {
    assert_false(expr.eval(Map([("age", @qx.Value::Int(age))])))
  }
  for age in [19L, 64L] {
    assert_true(expr.eval(Map([("age", @qx.Value::Int(age))])))
  }
}

///|
test "boolean combinations accept only boolean producing filters" {
  let expr = @queryx.import_filter(
    {
      "and": [
        { "===": [{ "var": "status" }, "vip"] },
        { "!": { "!=": [{ "var": "active" }, true] } },
        {
          "or": [
            { "<": [{ "var": "age" }, 25] },
            { ">": [{ "var": "age" }, 60] },
          ],
        },
      ],
    },
    fields(),
  )
  let values = Map([
    ("status", @qx.Value::String("vip")),
    ("active", @qx.Value::Bool(true)),
    ("age", @qx.Value::Int(20L)),
  ])
  assert_true(expr.eval(values))
  values.set("active", @qx.Value::Bool(false))
  assert_false(expr.eval(values))
}

///|
test "same type equality accepts each spelling and constant on either side" {
  for op in ["==", "===", "!=", "!=="] {
    let rule = Json::object(
      Map([(op, Json::array(["vip", { "var": "status" }]))]),
    )
    let expr = @queryx.import_filter(rule, fields())
    let expected = op == "==" || op == "==="
    assert_eq(expr.eval(Map([("status", @qx.Value::String("vip"))])), expected)
  }
}

///|
test "implicit conversions and string or bool ordering are rejected" {
  expect_rule_error({ ">=": [{ "var": "age" }, "18"] }, "/>=/1")
  expect_rule_error({ "==": [{ "var": "active" }, 1] }, "/==/1")
  expect_rule_error({ "==": [{ "var": "status" }, null] }, "/==/1")
  expect_rule_error({ ">": [{ "var": "status" }, "a"] }, "/>")
  expect_rule_error({ "<=": [{ "var": "active" }, true] }, "/<=")
}

///|
test "var must be one declared static top level field without a default" {
  expect_rule_error({ "==": [{ "var": "missing" }, 18] }, "/==/0/var")
  expect_rule_error({ "==": [{ "var": "user.age" }, 18] }, "/==/0/var")
  expect_rule_error({ "==": [{ "var": "" }, 18] }, "/==/0/var")
  expect_rule_error({ "==": [{ "var": ["age", 18] }, 18] }, "/==/0/var")
  expect_rule_error(
    { "==": [{ "var": { "cat": ["a", "ge"] } }, 18] },
    "/==/0/var",
  )
  expect_rule_error({ "==": [{ "var": "age" }, { "var": "age" }] }, "/==")
}

///|
test "empty combinations malformed arities and literal values cannot reach SQL bridge" {
  expect_rule_error({ "and": [] }, "/and")
  expect_rule_error({ "or": [] }, "/or")
  expect_rule_error({ "!": [] }, "/!")
  expect_rule_error({ "!": [true, false] }, "/!")
  expect_rule_error({ "<": [1, { "var": "age" }, 20] }, "/<")
  expect_rule_error(true, "")
  expect_rule_error({ "var": "active" }, "/var")
  expect_rule_error(
    { "and": [{ "==": [{ "var": "active" }, true] }, 1] },
    "/and/1",
  )
  expect_rule_error({ "a": { "==": [{ "var": "age" }, 18] }, "b": 2 }, "")
}

///|
test "unsupported branches are rejected even when a preceding condition would short circuit" {
  expect_rule_error(
    {
      "or": [
        { "==": [{ "var": "active" }, true] },
        { "map": [[1], { "var": "" }] },
      ],
    },
    "/or/1/map",
  )
}

///|
test "input budgets count the full JSON input and reject invalid configuration" {
  let rule : Json = { "==": [{ "var": "age" }, 18] }
  let _ = @queryx.import_filter(rule, fields(), max_nodes=5, max_depth=3)
  try {
    let _ = @queryx.import_filter(rule, fields(), max_nodes=4)
    fail("expected node budget rejection")
  } catch {
    @queryx.LimitExceeded(path) => assert_eq(path, "/==/1")
    _ => fail("wrong error")
  }
  try {
    let _ = @queryx.import_filter(rule, fields(), max_depth=2)
    fail("expected depth budget rejection")
  } catch {
    @queryx.LimitExceeded(path) => assert_eq(path, "/==/0/var")
    _ => fail("wrong error")
  }
  try {
    let _ = @queryx.import_filter(rule, fields(), max_nodes=0)
    fail("expected invalid configuration")
  } catch {
    @queryx.InvalidFields(_, _) => ()
    _ => fail("wrong error")
  }
}

///|
test "numeric constants and records respect both Int32 boundaries" {
  for n in [-2147483648.0, 2147483647.0] {
    let _ = @queryx.import_filter(
      { "==": [{ "var": "age" }, n.to_json()] },
      fields(),
    )
    @queryx.validate_record(
      { "age": n.to_json(), "status": "vip", "active": true },
      fields(),
    )
  }
  for n in [-2147483649.0, 2147483648.0, 18.5] {
    expect_rule_error({ "==": [{ "var": "age" }, n.to_json()] }, "/==/1")
    try {
      @queryx.validate_record(
        { "age": n.to_json(), "status": "vip", "active": true },
        fields(),
      )
      fail("expected invalid numeric record")
    } catch {
      @queryx.InvalidRecord(path, _) => assert_eq(path, "/age")
      _ => fail("wrong error")
    }
  }
}

///|
test "record validation requires non null fields and refuses type conversions" {
  @queryx.validate_record(
    { "age": 18, "status": "vip", "active": true, "extra": [] },
    fields(),
  )
  let one : Array[@queryx.Field] = [
    { name: "age", kind: @queryx.FieldType::Number, },
  ]
  for
    record in (
      [{}, { "age": null }, { "age": "18" }, { "age": true }] : Array[Json]) {
    try {
      @queryx.validate_record(record, one)
      fail("expected invalid record")
    } catch {
      @queryx.InvalidRecord(path, _) => assert_eq(path, "/age")
      _ => fail("wrong error")
    }
  }
}

///|
test "JSON pointers escape keys and unsupported operation names" {
  expect_rule_error({ "bad/op~": [] }, "/bad~1op~0")
  let escaped : Array[@queryx.Field] = [
    { name: "a/b~c", kind: @queryx.FieldType::Number, },
  ]
  let _ = @queryx.import_filter({ "==": [{ "var": "a/b~c" }, 1] }, escaped)
  try {
    @queryx.validate_record({ "a/b~c": null }, escaped)
    fail("expected escaped field error")
  } catch {
    @queryx.InvalidRecord(path, _) => assert_eq(path, "/a~1b~0c")
    _ => fail("wrong error")
  }
}

///|
test "field declarations reject duplicate dotted and empty names" {
  let invalid : Array[Array[@queryx.Field]] = [
    [
      { name: "age", kind: @queryx.FieldType::Number, },
      { name: "age", kind: @queryx.FieldType::String, },
    ],
    [{ name: "user.age", kind: @queryx.FieldType::Number, }],
    [{ name: "", kind: @queryx.FieldType::Number, }],
  ]
  for declarations in invalid {
    try {
      let _ = @queryx.import_filter(
        { "==": [{ "var": "age" }, 18] },
        declarations,
      )
      fail("expected invalid declarations")
    } catch {
      @queryx.InvalidFields(_, _) => ()
      _ => fail("wrong error")
    }
  }
}

///|
test "Unicode is preserved and PostgreSQL NUL is rejected" {
  let expr = @queryx.import_filter(
    { "===": [{ "var": "status" }, "🌙月"] },
    fields(),
  )
  @queryx.validate_record(
    { "age": 18, "status": "🌙月", "active": true },
    fields(),
  )
  assert_true(expr.eval(Map([("status", @qx.Value::String("🌙月"))])))
  let nul = @json.parse("\"a\\u0000b\"")
  expect_rule_error({ "===": [{ "var": "status" }, nul] }, "/===/1")
}

///|
test "extra record structure remains subject to the input depth budget" {
  try {
    @queryx.validate_record(
      { "age": 18, "status": "vip", "active": true, "extra": [[[1]]] },
      fields(),
      max_depth=2,
    )
    fail("expected bounded validation")
  } catch {
    @queryx.LimitExceeded(_) => ()
    _ => fail("wrong error")
  }
}

///|
test "non-finite values cannot enter rules or extra record fields" {
  let infinity = Json::number(@double.infinity)
  expect_rule_error({ "==": [{ "var": "age" }, infinity] }, "/==/1")
  try {
    @queryx.validate_record(
      { "age": 18, "status": "vip", "active": true, "extra": infinity },
      fields(),
    )
    fail("expected invalid extra record number")
  } catch {
    @queryx.InvalidRecord(path, _) => assert_eq(path, "/extra")
    _ => fail("wrong error")
  }
}
