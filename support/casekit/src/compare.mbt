///|
/// Category of an observable difference.
pub(all) enum DifferenceKind {
  MissingCase
  ExtraCase
  ValueMismatch
  TypeMismatch
  MissingField
  ExtraField
} derive(Eq, ToJson)

///|
/// A difference at a JSON Pointer path within a case. The empty path is its root.
pub(all) struct Difference {
  case_id : String
  path : String
  kind : DifferenceKind
  expected : Json?
  actual : Json?
} derive(ToJson)

///|
/// Comparison result. An error reading inputs is raised, never represented as a match.
pub(all) struct Report {
  suite : String
  total_cases : Int
  matched_cases : Int
  abs_tol : Double
  rel_tol : Double
  differences : Array[Difference]
} derive(ToJson)

///|
pub fn Report::is_match(self : Report) -> Bool {
  self.differences.is_empty()
}

///|
fn keys_union(a : Map[String, Json], b : Map[String, Json]) -> Array[String] {
  let ids = a.keys().to_array()
  for id, _ in b {
    if !a.contains(id) {
      ids.push(id)
    }
  }
  ids.sort_by((a, b) => a.lexical_compare(b))
  ids
}

///|
/// Compare case IDs, ignoring observation order. Missing and extra cases are differences.
pub fn compare(
  expected : Suite,
  actual : Suite,
  abs_tol? : Double = 0.0,
  rel_tol? : Double = 0.0,
) -> Report raise CaseError {
  for tolerance in [abs_tol, rel_tol] {
    if tolerance < 0.0 || tolerance.is_nan() || tolerance.is_inf() {
      raise Invalid("tolerances must be finite and nonnegative")
    }
  }
  if expected.name != actual.name {
    raise Invalid("suite names differ")
  }
  if expected.size() == 0 || actual.size() == 0 {
    raise Invalid("cannot compare empty suites")
  }
  let ids = keys_union(expected.values, actual.values)
  let differences : Array[Difference] = []
  let mut matched = 0
  for id in ids {
    let left = expected.values.get(id)
    let right = actual.values.get(id)
    match (left, right) {
      (Some(a), Some(b)) => {
        validate_value(a, 0)
        validate_value(b, 0)
        let before = differences.length()
        diff_values(id, "", a, b, differences, abs_tol, rel_tol)
        if differences.length() == before {
          matched += 1
        }
      }
      (Some(_), None) =>
        differences.push({
          case_id: id,
          path: "",
          kind: MissingCase,
          expected: left,
          actual: right,
        })
      (None, Some(_)) =>
        differences.push({
          case_id: id,
          path: "",
          kind: ExtraCase,
          expected: left,
          actual: right,
        })
      (None, None) => ()
    }
  }
  {
    suite: expected.name,
    abs_tol,
    rel_tol,
    total_cases: ids.length(),
    matched_cases: matched,
    differences,
  }
}

///|
pub extend DifferenceKind with Eq::{equal, not_equal}

///|
pub extend DifferenceKind with ToJson::{to_json}

///|
pub extend Difference with ToJson::{to_json}

///|
pub extend Report with ToJson::{to_json}
