///|
/// Errors in a suite's identity or recorded values.
pub(all) suberror CaseError {
  Invalid(String)
}

///|
/// A named collection of observations, keyed by a stable case identifier.
pub struct Suite {
  name : String
  priv values : Map[String, Json]
}

///|
/// Create a suite. Use the same name on each backend.
pub fn Suite::new(name : String) -> Suite raise CaseError {
  if name.trim().is_empty() {
    raise Invalid("suite name must not be empty")
  }
  { name, values: {}, }
}

///|
fn validate_value(value : Json, depth : Int) -> Unit raise CaseError {
  if depth > 64 {
    raise Invalid("observation exceeds 64 levels of nesting")
  }
  match value {
    Number(n, ..) =>
      if n.is_nan() || n.is_inf() {
        raise Invalid("non-finite number: record an explicit string instead")
      }
    Array(xs) =>
      for x in xs {
        validate_value(x, depth + 1)
      }
    Object(xs) =>
      for _, x in xs {
        validate_value(x, depth + 1)
      }
    _ => ()
  }
}

///|
/// Record a value. Case IDs must be unique within a suite.
pub fn Suite::observe(
  self : Suite,
  id : String,
  value : Json,
) -> Unit raise CaseError {
  if id.trim().is_empty() {
    raise Invalid("case ID must not be empty")
  }
  if self.values.contains(id) {
    raise Invalid("duplicate case ID: \{id}")
  }
  let json = value
  validate_value(json, 0)
  self.values[id] = copy_value(json)
}

///|
/// Number of recorded cases.
pub fn Suite::size(self : Suite) -> Int {
  self.values.length()
}

///|
/// Encode a versioned observation document. No diagnostic text is included.
pub fn Suite::encode(self : Suite) -> String raise CaseError {
  if self.values.is_empty() {
    raise Invalid("cannot encode an empty suite")
  }
  let ids = self.values.keys().to_array()
  ids.sort_by((a, b) => a.lexical_compare(b))
  let cases : Array[Json] = ids.map(id => {
    "id": id.to_json(),
    "value": self.values[id],
  })
  let doc : Json = {
    "casekit": 1,
    "suite": self.name.to_json(),
    "cases": cases.to_json(),
  }
  canonical(doc)
}

///|
/// Record a floating-point value without silently converting NaN or infinity to null.
pub fn Suite::observe_number(
  self : Suite,
  id : String,
  value : Double,
) -> Unit raise CaseError {
  if value.is_nan() || value.is_inf() {
    raise Invalid("non-finite number: record an explicit string instead")
  }
  self.observe(id, value.to_json())
}
