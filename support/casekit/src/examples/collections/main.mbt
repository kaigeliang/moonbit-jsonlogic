///|
fn main raise {
  let s = @casekit.Suite::new("collection-behavior")
  let values = [5, 1, 5, -2, 9]
  values.sort()
  s.observe("sort/duplicates", values.to_json())
  let counts : Map[String, Int] = Map([])
  for word in ["moon", "bit", "moon", "你好"] {
    counts[word] = counts.get(word).unwrap_or(0) + 1
  }
  s.observe("map/counts", counts.to_json())
  s.observe("sort/filtered", values.filter(x => x > 0).to_json())
  println(s.encode())
}
