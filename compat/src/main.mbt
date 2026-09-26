///|
fn main raise {
  let suite = @casekit.Suite::new("jsonlogic-2.0.5")
  for (id, rule, data) in cases() {
    let value = @logic.apply_json(rule, data) catch {
      error => fail(id + ": " + error.to_string())
    }
    suite.observe(id, value)
  }
  println(suite.encode())
}
