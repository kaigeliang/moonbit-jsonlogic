///|
fn main raise {
  let observations : Array[Json] = []
  for (id, rule, data) in cases() {
    let value = @logic.apply_json(rule, data) catch {
      error => fail(id + ": " + error.to_string())
    }
    observations.push({ "id": id, "value": value })
  }
  let result : Json = { "suite": "jsonlogic-2.0.5", "cases": observations }
  println(result.stringify())
}
