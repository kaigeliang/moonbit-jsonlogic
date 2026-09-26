///|
fn pointer_key(key : String) -> String {
  key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn value_kind(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn diff_values(
  id : String,
  path : String,
  a : Json,
  b : Json,
  output : Array[Difference],
  abs_tol : Double,
  rel_tol : Double,
) -> Unit {
  match (a, b) {
    (Number(x, repr=left_repr), Number(y, repr=right_repr)) => {
      let exact = if left_repr is Some(_) || right_repr is Some(_) {
        a.stringify() == b.stringify()
      } else {
        x == y
      }
      let approximate = (abs_tol > 0.0 || rel_tol > 0.0) &&
        numbers_close(x, y, abs_tol, rel_tol)
      if !exact && !approximate {
        output.push({
          case_id: id,
          path,
          kind: ValueMismatch,
          expected: Some(a),
          actual: Some(b),
        })
      }
    }
    (Object(left), Object(right)) =>
      for key in keys_union(left, right) {
        let at = path + "/" + pointer_key(key)
        match (left.get(key), right.get(key)) {
          (Some(x), Some(y)) =>
            diff_values(id, at, x, y, output, abs_tol, rel_tol)
          (x, None) =>
            output.push({
              case_id: id,
              path: at,
              kind: MissingField,
              expected: x,
              actual: None,
            })
          (None, y) =>
            output.push({
              case_id: id,
              path: at,
              kind: ExtraField,
              expected: None,
              actual: y,
            })
        }
      }
    (Array(left), Array(right)) => {
      let length = if left.length() > right.length() {
        left.length()
      } else {
        right.length()
      }
      for i = 0; i < length; i = i + 1 {
        let at = path + "/" + i.to_string()
        if i >= left.length() {
          output.push({
            case_id: id,
            path: at,
            kind: ExtraField,
            expected: None,
            actual: Some(right[i]),
          })
        } else if i >= right.length() {
          output.push({
            case_id: id,
            path: at,
            kind: MissingField,
            expected: Some(left[i]),
            actual: None,
          })
        } else {
          diff_values(id, at, left[i], right[i], output, abs_tol, rel_tol)
        }
      }
    }
    _ =>
      if a != b {
        output.push({
          case_id: id,
          path,
          kind: if value_kind(a) == value_kind(b) {
            ValueMismatch
          } else {
            TypeMismatch
          },
          expected: Some(a),
          actual: Some(b),
        })
      }
  }
}

///|
fn numbers_close(
  a : Double,
  b : Double,
  abs_tol : Double,
  rel_tol : Double,
) -> Bool {
  if a == b {
    return true
  }
  if abs_tol > 0.0 && (a - b).abs() <= abs_tol {
    return true
  }
  if rel_tol == 0.0 {
    return false
  }
  let scale = if a.abs() > b.abs() { a.abs() } else { b.abs() }
  scale > 0.0 && (a / scale - b / scale).abs() <= rel_tol
}
