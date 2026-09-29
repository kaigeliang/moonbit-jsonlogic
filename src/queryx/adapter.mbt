///|
/// The first adapter accepts non-null scalar fields. Number is an Int32 integer:
/// queryx 0.2.1 narrows Int64 values to Int when passing them to foxql 0.1.3.
pub(all) enum FieldType {
  Number
  String
  Bool
} derive(Eq)

///|
pub extend FieldType with Eq::{equal, not_equal}

///|
/// A declared top-level data key. SQL column mapping remains FieldResolver's job.
pub(all) struct Field {
  name : String
  kind : FieldType
}

///|
/// Locations are JSON Pointers. Field declaration errors use /fields/<index>/name.
pub(all) suberror ImportError {
  InvalidRule(String, String)
  InvalidRecord(String, String)
  InvalidFields(String, String)
  LimitExceeded(String)
}

///|
pub fn ImportError::to_string(self : ImportError) -> String {
  match self {
    InvalidRule(path, reason) => "invalid filter at " + path + ": " + reason
    InvalidRecord(path, reason) => "invalid record at " + path + ": " + reason
    InvalidFields(path, reason) => "invalid fields at " + path + ": " + reason
    LimitExceeded(path) => "adapter input limit exceeded at " + path
  }
}

///|
priv struct InputBudget {
  mut remaining : Int
  max_depth : Int
}

///|
fn input_budget(
  max_nodes : Int,
  max_depth : Int,
) -> InputBudget raise ImportError {
  if max_nodes <= 0 || max_depth < 1 || max_depth > 128 {
    raise InvalidFields(
      "", "max_nodes must be positive and max_depth must be between 1 and 128",
    )
  }
  { remaining: max_nodes, max_depth, }
}

///|
fn pointer(path : String, key : String) -> String {
  path + "/" + key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn text_is_valid(text : String) -> Bool {
  let mut i = 0
  while i < text.length() {
    let unit = text[i]
    if unit == 0 {
      return false
    }
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= text.length() || text[i + 1] < 0xDC00 || text[i + 1] > 0xDFFF {
        return false
      }
      i += 2
    } else {
      if unit >= 0xDC00 && unit <= 0xDFFF {
        return false
      }
      i += 1
    }
  }
  true
}

///|
fn fail_input(
  path : String,
  reason : String,
  record : Bool,
) -> Unit raise ImportError {
  if record {
    raise InvalidRecord(path, reason)
  } else {
    raise InvalidRule(path, reason)
  }
}

///|
// Count every JSON value, including wrappers and unused or literal subtrees.
// The subsequent translation visits a subset of these nodes without execution.
fn check_input(
  value : Json,
  budget : InputBudget,
  depth : Int,
  path : String,
  record : Bool,
) -> Unit raise ImportError {
  if depth > budget.max_depth || budget.remaining <= 0 {
    raise LimitExceeded(path)
  }
  budget.remaining -= 1
  match value {
    Json::Number(n, ..) =>
      if n.is_nan() || n.is_inf() {
        fail_input(path, "non-finite numbers are not supported", record)
      }
    Json::String(text) =>
      if !text_is_valid(text) {
        fail_input(
          path, "strings must have valid Unicode and contain no NUL", record,
        )
      }
    Json::Array(values) =>
      for i, item in values {
        check_input(
          item,
          budget,
          depth + 1,
          pointer(path, i.to_string()),
          record,
        )
      }
    Json::Object(fields) =>
      for key, item in fields {
        let item_path = pointer(path, key)
        if !text_is_valid(key) {
          fail_input(
            item_path, "object keys must have valid Unicode and contain no NUL",
            record,
          )
        }
        check_input(item, budget, depth + 1, item_path, record)
      }
    _ => ()
  }
}

///|
fn field_types(
  fields : Array[Field],
) -> Map[String, FieldType] raise ImportError {
  if fields.is_empty() || fields.length() > 1000 {
    raise InvalidFields("/fields", "declare between 1 and 1000 fields")
  }
  let kinds : Map[String, FieldType] = Map([])
  for i, field in fields {
    let path = "/fields/" + i.to_string() + "/name"
    if field.name.is_empty() || field.name.contains(".") {
      raise InvalidFields(
        path, "field names must be non-empty top-level keys without dots",
      )
    }
    if field.name.length() > 1024 || !text_is_valid(field.name) {
      raise InvalidFields(
        path, "field name is too long or contains invalid Unicode or NUL",
      )
    }
    if kinds.contains(field.name) {
      raise InvalidFields(path, "duplicate field declaration: " + field.name)
    }
    kinds.set(field.name, field.kind)
  }
  kinds
}

///|
fn scalar_value(value : Json, kind : FieldType) -> @qx.Value? {
  match (value, kind) {
    (Json::Number(n, ..), FieldType::Number) =>
      if !n.is_nan() &&
        !n.is_inf() &&
        n >= -2147483648.0 &&
        n <= 2147483647.0 &&
        n == n.to_int().to_double() {
        Some(@qx.Value::Int(n.to_int().to_int64()))
      } else {
        None
      }
    (Json::String(text), FieldType::String) => Some(@qx.Value::String(text))
    (Json::True, FieldType::Bool) => Some(@qx.Value::Bool(true))
    (Json::False, FieldType::Bool) => Some(@qx.Value::Bool(false))
    _ => None
  }
}

///|
fn kind_name(kind : FieldType) -> String {
  match kind {
    FieldType::Number => "an Int32 integer"
    FieldType::String => "a string"
    FieldType::Bool => "a boolean"
  }
}

///|
/// Check the non-null, same-type data contract before evaluating imported rules.
/// Extra keys are allowed; the entire JSON input is bounded and checked for
/// finite numbers, valid Unicode and NUL. This does not validate database schema.
pub fn validate_record(
  data : Json,
  fields : Array[Field],
  max_nodes? : Int = 10000,
  max_depth? : Int = 64,
) -> Unit raise ImportError {
  let kinds = field_types(fields)
  check_input(data, input_budget(max_nodes, max_depth), 0, "", true)
  let values = match data {
    Json::Object(values) => values
    _ => raise InvalidRecord("", "records must be JSON objects")
  }
  for field, kind in kinds {
    let path = pointer("", field)
    match values.get(field) {
      None => raise InvalidRecord(path, "declared field is missing")
      Some(value) =>
        if scalar_value(value, kind) is None {
          raise InvalidRecord(
            path,
            "declared field must be non-null and " + kind_name(kind),
          )
        }
    }
  }
}

///|
fn is_var_rule(value : Json) -> Bool {
  match value {
    Json::Object(fields) => fields.length() == 1 && fields.contains("var")
    _ => false
  }
}

///|
fn read_field(
  value : Json,
  kinds : Map[String, FieldType],
  path : String,
) -> (String, FieldType) raise ImportError {
  let raw = match value {
    Json::Object(fields) if fields.length() == 1 && fields.contains("var") =>
      fields["var"]
    _ => raise InvalidRule(path, "expected a static var field reference")
  }
  let var_path = pointer(path, "var")
  let (key, key_path) = match raw {
    Json::Array(values) => {
      if values.length() != 1 {
        raise InvalidRule(var_path, "var must have one key and no fallback")
      }
      (values[0], pointer(var_path, "0"))
    }
    _ => (raw, var_path)
  }
  let name = match key {
    Json::String(name) if !name.is_empty() && !name.contains(".") => name
    _ => raise InvalidRule(key_path, "var must name one static top-level field")
  }
  match kinds.get(name) {
    Some(kind) => (name, kind)
    None => raise InvalidRule(key_path, "undeclared field: " + name)
  }
}

///|
fn comparison_op(op : String, reversed : Bool) -> @qx.CmpOp {
  match op {
    "==" | "===" => @qx.CmpOp::Eq
    "!=" | "!==" => @qx.CmpOp::Ne
    ">" => if reversed { @qx.CmpOp::Lt } else { @qx.CmpOp::Gt }
    ">=" => if reversed { @qx.CmpOp::Le } else { @qx.CmpOp::Ge }
    "<" => if reversed { @qx.CmpOp::Gt } else { @qx.CmpOp::Lt }
    _ => if reversed { @qx.CmpOp::Ge } else { @qx.CmpOp::Le }
  }
}

///|
fn translate(
  rule : Json,
  kinds : Map[String, FieldType],
  path : String,
) -> @qx.Expr raise ImportError {
  let fields = match rule {
    Json::Object(fields) if fields.length() == 1 => fields
    _ => raise InvalidRule(path, "expected a single-operation filter object")
  }
  let op = fields.keys().to_array()[0]
  let raw = fields[op]
  let op_path = pointer(path, op)
  let values = match raw {
    Json::Array(values) => values
    _ => [raw]
  }
  let child_path = (i : Int) => {
    match raw {
      Json::Array(_) => pointer(op_path, i.to_string())
      _ => op_path
    }
  }
  match op {
    "and" | "or" => {
      if values.is_empty() {
        raise InvalidRule(op_path, "boolean combinations must be non-empty")
      }
      let clauses : Array[@qx.Expr] = []
      for i, value in values {
        clauses.push(translate(value, kinds, child_path(i)))
      }
      if op == "and" {
        @qx.Expr::And(clauses)
      } else {
        @qx.Expr::Or(clauses)
      }
    }
    "!" => {
      if values.length() != 1 {
        raise InvalidRule(op_path, "not requires exactly one boolean filter")
      }
      @qx.Expr::Not(translate(values[0], kinds, child_path(0)))
    }
    "==" | "===" | "!=" | "!==" | ">" | ">=" | "<" | "<=" => {
      if values.length() != 2 {
        raise InvalidRule(op_path, "comparisons require exactly two operands")
      }
      let left_var = is_var_rule(values[0])
      let right_var = is_var_rule(values[1])
      if left_var == right_var {
        raise InvalidRule(
          op_path, "comparison requires one field and one scalar constant",
        )
      }
      let field_index = if left_var { 0 } else { 1 }
      let constant_index = if left_var { 1 } else { 0 }
      let (name, kind) = read_field(
        values[field_index],
        kinds,
        child_path(field_index),
      )
      if kind != FieldType::Number &&
        op != "==" &&
        op != "===" &&
        op != "!=" &&
        op != "!==" {
        raise InvalidRule(op_path, "ordered comparisons require an Int32 field")
      }
      let value = match scalar_value(values[constant_index], kind) {
        Some(value) => value
        None =>
          raise InvalidRule(
            child_path(constant_index),
            "constant must be non-null and " + kind_name(kind),
          )
      }
      @qx.Expr::Compare(name, comparison_op(op, right_var), value)
    }
    _ => raise InvalidRule(op_path, "unsupported operation: " + op)
  }
}

///|
/// Import a bounded JSONLogic filter directly into a QueryX expression tree.
/// Only field/constant same-type comparisons and non-empty and/or/! combinations
/// are accepted. Every resulting node is supported by QueryX's foxql bridge.
/// Call validate_record before local evaluation; SQL requires matching non-null
/// INTEGER/TEXT/BOOLEAN columns and bytewise text equality (PostgreSQL C collation).
/// Do not round-trip Expr through QueryX JSON serialization before execution.
pub fn import_filter(
  rule : Json,
  fields : Array[Field],
  max_nodes? : Int = 10000,
  max_depth? : Int = 64,
) -> @qx.Expr raise ImportError {
  let kinds = field_types(fields)
  check_input(rule, input_budget(max_nodes, max_depth), 0, "", false)
  translate(rule, kinds, "")
}
