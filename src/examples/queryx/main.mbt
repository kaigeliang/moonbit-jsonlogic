// This native executable is the JSON protocol used by tools/check_queryx.py.
// QueryX expressions stay in memory: their JSON serialization is not used.

///|
struct Resolver {
  columns : Map[String, @ast.ColumnRef]
}

///|
impl @foxql.FieldResolver for Resolver with fn resolve_column(self, field) {
  self.columns.get(field)
}

///|
impl @foxql.FieldResolver for Resolver with fn table_name(_self) {
  "jl_rows"
}

///|
fn property(value : Json, key : String) -> Json raise {
  match value {
    Object(object) =>
      match object.get(key) {
        Some(item) => item
        None => fail("missing fixture property: " + key)
      }
    _ => fail("fixture value must be an object")
  }
}

///|
fn as_string(value : Json) -> String raise {
  match value {
    String(text) => text
    _ => fail("fixture value must be a string")
  }
}

///|
fn as_array(value : Json) -> Array[Json] raise {
  match value {
    Array(items) => items
    _ => fail("fixture value must be an array")
  }
}

///|
fn fields_from_schema(schema : Json) -> Array[@adapter.Field] raise {
  let fields : Array[@adapter.Field] = []
  match schema {
    Object(object) =>
      for name, kind in object {
        let kind = match as_string(kind) {
          "int32" => @adapter.Number
          "string" => @adapter.String
          "bool" => @adapter.Bool
          other => fail("unknown fixture field type: " + other)
        }
        fields.push(@adapter.Field::{ name, kind, })
      }
    _ => fail("fixture schema must be an object")
  }
  fields
}

///|
fn value_from_json(value : Json) -> @qx.Value raise {
  match value {
    Number(number, ..) => @qx.Int(number.to_int64())
    String(text) => @qx.String(text)
    True => @qx.Bool(true)
    False => @qx.Bool(false)
    _ => fail("validated record contains a non-scalar field")
  }
}

///|
fn parameter_json(value : @ast.Value) -> Json raise {
  match value {
    @ast.Int(number) => { "type": "int32", "value": number }
    @ast.String(text) => { "type": "string", "value": text }
    @ast.Bool(value) => { "type": "bool", "value": value }
    _ => fail("SQL bridge produced a parameter outside the admitted types")
  }
}

///|
fn run_query(query : Json) -> Json raise {
  let id = as_string(property(query, "id"))
  let fields = fields_from_schema(property(query, "schema"))
  let rule = property(query, "rule")
  let expression = @adapter.import_filter(rule, fields)
  let columns : Map[String, @ast.ColumnRef] = Map([])
  let sql_fields : Array[Json] = []
  for index, field in fields {
    let column = "f" + index.to_string()
    columns.set(field.name, @ast.ColumnRef::{ name: column, table: "jl_rows", })
    let kind = match field.kind {
      @adapter.Number => "int32"
      @adapter.String => "string"
      @adapter.Bool => "bool"
    }
    sql_fields.push({ "field": field.name, "column": column, "type": kind })
  }
  let resolver = Resolver::{ columns, }
  let where_clause = @qx.to_foxql_expr(expression, resolver)
  let id_column = @ast.ColumnRef::{ name: "id", table: "jl_rows", }
  let (sql, parameters) = @builder.SelectBuilder::new(
      @builder.Table::new("jl_rows"),
      [id_column],
    )
    .where_(where_clause)
    .order_by(@ast.OrderByClause::{ column: id_column, direction: @ast.Asc, })
    .to_sql()
  let core_ids : Array[Json] = []
  let queryx_ids : Array[Json] = []
  let observations : Array[Json] = []
  for record in as_array(property(query, "data")) {
    @adapter.validate_record(record, fields)
    let record_id = property(record, "id")
    let values : Map[String, @qx.Value] = Map([])
    for field in fields {
      values.set(field.name, value_from_json(property(record, field.name)))
    }
    let core_value = @logic.apply(rule, record)
    let core_match = match core_value {
      True => true
      False => false
      _ => fail("admitted rule did not return a boolean")
    }
    let queryx_match = expression.eval(values)
    if core_match {
      core_ids.push(record_id)
    }
    if queryx_match {
      queryx_ids.push(record_id)
    }
    observations.push({
      "id": record_id,
      "core": core_match,
      "queryx": queryx_match,
    })
  }
  {
    "id": id,
    "core_ids": core_ids,
    "queryx_ids": queryx_ids,
    "records": observations,
    "sql": sql,
    "parameters": parameters.map(parameter_json),
    "fields": sql_fields,
    "expression_debug": @debug.to_string(expression),
  }
}

///|
fn import_diagnostic(error : @adapter.ImportError) -> Json {
  let (kind, path, reason) = match error {
    @adapter.InvalidRule(path, reason) => ("InvalidRule", path, reason)
    @adapter.InvalidRecord(path, reason) => ("InvalidRecord", path, reason)
    @adapter.InvalidFields(path, reason) => ("InvalidFields", path, reason)
    @adapter.LimitExceeded(path) =>
      ("LimitExceeded", path, "adapter input budget exceeded")
  }
  { "kind": kind, "path": path, "reason": reason, "message": error.to_string() }
}

///|
fn reject_rule(query : Json) -> Json raise {
  let id = as_string(property(query, "id"))
  let fields = fields_from_schema(property(query, "schema"))
  let rule = property(query, "rule")
  let error = try {
    @adapter.import_filter(rule, fields) |> ignore
    None
  } catch {
    error => Some(import_diagnostic(error))
  }
  {
    "id": id,
    "rejected": error is Some(_),
    "error": match error {
      Some(details) => details
      None => Json::null()
    },
  }
}

///|
fn reject_record(query : Json) -> Json raise {
  let id = as_string(property(query, "id"))
  let fields = fields_from_schema(property(query, "schema"))
  let record = property(query, "data")
  let error = try {
    @adapter.validate_record(record, fields)
    None
  } catch {
    error => Some(import_diagnostic(error))
  }
  {
    "id": id,
    "rejected": error is Some(_),
    "error": match error {
      Some(details) => details
      None => Json::null()
    },
  }
}

///|
fn main raise {
  let args = @env.args()
  if args.length() != 2 {
    fail(
      "Usage: moon run src/examples/queryx --target native -- <fixture-json>",
    )
  }
  let fixture = @json.parse(args[1])
  let result : Json = {
    "protocol": "jsonlogic-queryx-check/1",
    "target": "native",
    "queries": as_array(property(fixture, "queries")).map(run_query),
    "rejections": as_array(property(fixture, "rejections")).map(reject_rule),
    "record_rejections": as_array(property(fixture, "record_rejections")).map(
      reject_record,
    ),
  }
  println(result.stringify())
}
