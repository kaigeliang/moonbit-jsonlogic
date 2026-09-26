///|
// Deliberately different candidates show how to inspect a mismatch locally.
fn main raise {
  let before = @casekit.Suite::new("intentional-canary")
  let after = @casekit.Suite::new("intentional-canary")
  before.observe("sorted", [1, 2, 3])
  after.observe("sorted", [1, 3, 2])
  before.observe("metadata", { "count": 3, "ready": true })
  after.observe("metadata", { "count": 3, "ready": "true" })
  let report = @casekit.compare(before, after)
  assert_false(report.is_match())
  println(report.render())
}
