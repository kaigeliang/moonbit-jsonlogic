///|
fn main raise {
  let data : Json = {
    "account_type": "business",
    "email": "dev@example.com",
    "company": "",
  }
  let show_company : Json = { "==": [{ "var": "account_type" }, "business"] }
  let required : Json = {
    "missing": { "if": [show_company, ["email", "company"], ["email"]] },
  }
  let visible = @logic.apply(show_company, data)
  let missing = @logic.apply(required, data)
  assert_eq(visible, true)
  assert_eq(missing, ["company"])
  let result : Json = { "show_company": visible, "missing_required": missing }
  println(result.stringify())
}
