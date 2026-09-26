///|
fn main raise {
  let data : Json = {
    "users": [
      { "name": "Ada", "active": true, "score": 80 },
      { "name": "Lin", "active": false, "score": 95 },
      { "name": "Ming", "active": true, "score": 90 },
    ],
  }
  let rule : Json = {
    "map": [
      {
        "filter": [
          { "var": "users" },
          { "and": [{ "var": "active" }, { ">=": [{ "var": "score" }, 85] }] },
        ],
      },
      { "var": "name" },
    ],
  }
  let names = @logic.apply(rule, data)
  assert_eq(names, ["Ming"])
  println(names.stringify())
}
