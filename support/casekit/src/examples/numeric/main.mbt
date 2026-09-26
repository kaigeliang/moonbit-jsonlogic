///|
fn main raise {
  let s = @casekit.Suite::new("numeric-behavior")
  s.observe_number("decimal/sum", 0.1 + 0.2)
  s.observe_number("zero/negative", -0.0)
  s.observe("integer/large", 9223372036854775807L.to_string().to_json())
  let values = [8, 3, 5, 3]
  s.observe("integer/sum", values.fold(init=0, (a, b) => a + b).to_json())
  println(s.encode())
}
