///|
/// Errors include a JSON Pointer into the rule whenever evaluation is involved.
pub(all) suberror LogicError {
  InvalidRule(String, String)
  LimitExceeded(String)
  NonFiniteNumber(String)
  InvalidInput(String)
}

///|
/// The value and captured log operations from one evaluation.
pub(all) struct Evaluation {
  value : Json
  logs : Array[Json]
  steps_used : Int
}

///|
priv struct Context {
  mut remaining : Int
  max_depth : Int
  logs : Array[Json]
}

///|
fn Context::visit(
  self : Context,
  depth : Int,
  path : String,
) -> Unit raise LogicError {
  if depth > self.max_depth || self.remaining <= 0 {
    raise LimitExceeded(path)
  }
  self.remaining -= 1
}

///|
fn validate_input(
  value : Json,
  ctx : Context,
  depth : Int,
) -> Unit raise LogicError {
  ctx.visit(depth, "")
  match value {
    Number(n, ..) =>
      if n.is_nan() || n.is_inf() {
        raise InvalidInput("input contains a non-finite number")
      }
    Array(xs) =>
      for x in xs {
        validate_input(x, ctx, depth + 1)
      }
    Object(xs) =>
      for key, x in xs {
        if has_unpaired_surrogate(key) {
          raise InvalidInput("object key contains an unpaired UTF-16 surrogate")
        }
        validate_input(x, ctx, depth + 1)
      }
    String(s) =>
      if has_unpaired_surrogate(s) {
        raise InvalidInput("input contains an unpaired UTF-16 surrogate")
      }
    _ => ()
  }
}

///|
/// Evaluate a rule with bounded input traversal and execution. Logs are captured, not printed.
pub fn evaluate(
  rule : Json,
  data : Json,
  max_steps? : Int = 100000,
  max_depth? : Int = 128,
) -> Evaluation raise LogicError {
  if max_steps <= 0 || max_depth < 1 || max_depth > 256 {
    raise InvalidInput(
      "max_steps must be positive and max_depth must be between 1 and 256",
    )
  }
  let ctx = { remaining: max_steps, max_depth, logs: [], }
  validate_input(rule, ctx, 0)
  validate_input(data, ctx, 0)
  let value = eval(rule, data, ctx, 0, "")
  { value, logs: ctx.logs, steps_used: max_steps - ctx.remaining, }
}

///|
/// Evaluate a JSONLogic rule. See evaluate for log capture and execution budgets.
pub fn apply(rule : Json, data : Json) -> Json raise LogicError {
  evaluate(rule, data).value
}

///|
/// Parse two JSON documents and evaluate. Parse failures are distinct from rule errors.
pub fn apply_json(rule : String, data : String) -> Json raise LogicError {
  if rule.length() > 2097152 || data.length() > 2097152 {
    raise InvalidInput("JSON document exceeds size limit")
  }
  let rule = @json.parse(rule) catch {
    _ => raise InvalidInput("invalid rule JSON")
  }
  let data = @json.parse(data) catch {
    _ => raise InvalidInput("invalid data JSON")
  }
  apply(rule, data)
}

///|
/// JSONLogic considers the empty array false and the string "0" true.
pub fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    Number(n, ..) => n != 0.0 && !n.is_nan()
    String(s) => !s.is_empty()
    Array(a) => !a.is_empty()
    _ => true
  }
}

///|
fn pointer(path : String, key : String) -> String {
  path + "/" + key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn arg(values : Array[Json], i : Int, path : String) -> Json raise LogicError {
  if i >= values.length() {
    raise InvalidRule(path, "missing argument " + i.to_string())
  }
  values[i]
}

///|
fn number_result(n : Double, path : String) -> Json raise LogicError {
  if n.is_nan() || n.is_inf() {
    raise NonFiniteNumber(path)
  }
  n.to_json()
}

///|
/// Render an evaluation failure with its rule location.
pub fn LogicError::to_string(self : LogicError) -> String {
  match self {
    InvalidRule(path, message) => "invalid rule at " + path + ": " + message
    LimitExceeded(path) => "evaluation limit exceeded at " + path
    NonFiniteNumber(path) => "non-finite result at " + path
    InvalidInput(message) => "invalid input: " + message
  }
}

///|
fn has_unpaired_surrogate(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c >= 0xD800 && c <= 0xDBFF {
      if i + 1 >= s.length() || s[i + 1] < 0xDC00 || s[i + 1] > 0xDFFF {
        return true
      }
      i += 2
    } else {
      if c >= 0xDC00 && c <= 0xDFFF {
        return true
      }
      i += 1
    }
  }
  false
}

///|
fn string_slice(
  s : String,
  start : Int,
  end : Int,
  path : String,
) -> Json raise LogicError {
  // Check code units before StringView::to_owned can normalize an incomplete pair.
  if start < end &&
    (
      (s[start] >= 0xDC00 && s[start] <= 0xDFFF) ||
      (s[end - 1] >= 0xD800 && s[end - 1] <= 0xDBFF)
    ) {
    raise InvalidRule(path, "operation produces an unpaired UTF-16 surrogate")
  }
  s[start:end].to_owned().to_json()
}
