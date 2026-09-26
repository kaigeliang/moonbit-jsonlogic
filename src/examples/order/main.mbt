///|
fn main raise {
  let data : Json = {
    "member": true,
    "items": [{ "price": 40, "quantity": 2 }, { "price": 30, "quantity": 1 }],
  }
  let subtotal : Json = {
    "reduce": [
      { "var": "items" },
      {
        "+": [
          { "var": "accumulator" },
          { "*": [{ "var": "current.price" }, { "var": "current.quantity" }] },
        ],
      },
      0,
    ],
  }
  let discount : Json = {
    "if": [{ "and": [{ "var": "member" }, { ">=": [subtotal, 100] }] }, 10, 0],
  }
  let total = @logic.apply(subtotal, data)
  let percentage = @logic.apply(discount, data)
  assert_eq(total, 110)
  assert_eq(percentage, 10)
  let result : Json = { "subtotal": total, "discount_percent": percentage }
  println(result.stringify())
}
