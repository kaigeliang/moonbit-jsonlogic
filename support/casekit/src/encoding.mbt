///|
/// Deterministic JSON serialization: object keys are sorted, array order is preserved.
pub fn canonical(value : Json) -> String raise CaseError {
  validate_value(value, 0)
  canonical_unchecked(value)
}

///|
fn canonical_unchecked(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().to_array()
      keys.sort_by((a, b) => a.lexical_compare(b))
      let parts = keys.map(key => {
        key.to_json().stringify() + ":" + canonical_unchecked(fields[key])
      })
      "{" + parts.join(",") + "}"
    }
    Array(xs) => "[" + xs.map(canonical_unchecked).join(",") + "]"
    _ => value.stringify()
  }
}

///|
fn copy_value(value : Json) -> Json {
  match value {
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      for key, item in fields {
        copied[key] = copy_value(item)
      }
      copied.to_json()
    }
    Array(xs) => xs.map(copy_value).to_json()
    _ => value
  }
}
