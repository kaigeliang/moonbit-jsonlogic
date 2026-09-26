// Ported from the operator/evaluation semantics of json-logic-js 2.0.5.
// Original copyright (c) 2015 Jeremy Wadhams, MIT; see third_party/json-logic-js/LICENSE.

///|
fn read_var(
  data : Json,
  key : Json,
  fallback : Json,
  path : String,
) -> Json raise LogicError {
  if key == Json::null() || key == "".to_json() {
    return data
  }
  let mut current = data
  for part in js_string(key).split(".") {
    let part = part.to_owned()
    match current {
      Object(fields) =>
        match fields.get(part) {
          Some(value) => current = value
          None => return fallback
        }
      Array(items) => {
        if part == "length" {
          current = items.length().to_json()
          continue
        }
        let i = @string.parse_int(part) catch { _ => return fallback }
        if i < 0 || i >= items.length() || i.to_string() != part {
          return fallback
        }
        current = items[i]
      }
      String(s) => {
        if part == "length" {
          current = s.length().to_json()
          continue
        }
        let i = @string.parse_int(part) catch { _ => return fallback }
        if i < 0 || i >= s.length() || i.to_string() != part {
          return fallback
        }
        current = string_slice(s, i, i + 1, path)
      }
      _ => return fallback
    }
  }
  current
}

///|
fn eval(
  rule : Json,
  data : Json,
  ctx : Context,
  depth : Int,
  path : String,
) -> Json raise LogicError {
  ctx.visit(depth, path)
  let (op, raw) = match rule {
    Array(xs) => {
      let result : Array[Json] = []
      for i, x in xs {
        result.push(eval(x, data, ctx, depth + 1, pointer(path, i.to_string())))
      }
      return result.to_json()
    }
    Object(fields) => {
      if fields.length() != 1 {
        return rule
      }
      let key = fields.keys().to_array()[0]
      (key, fields[key])
    }
    _ => return rule
  }
  let values = match raw {
    Array(xs) => xs
    _ => [raw]
  }
  let op_path = pointer(path, op)
  let child_path = (i : Int) => {
    match raw {
      Array(_) => pointer(op_path, i.to_string())
      _ => op_path
    }
  }
  match op {
    "if" | "?:" => {
      let mut i = 0
      while i + 1 < values.length() {
        if truthy(eval(values[i], data, ctx, depth + 1, child_path(i))) {
          return eval(values[i + 1], data, ctx, depth + 1, child_path(i + 1))
        }
        i += 2
      }
      return if i < values.length() {
        eval(values[i], data, ctx, depth + 1, child_path(i))
      } else {
        Json::null()
      }
    }
    "and" | "or" => {
      if values.is_empty() {
        raise InvalidRule(
          path, "empty and/or would produce JavaScript undefined",
        )
      }
      let mut result = Json::null()
      for i, value in values {
        result = eval(value, data, ctx, depth + 1, child_path(i))
        if (op == "and" && !truthy(result)) || (op == "or" && truthy(result)) {
          return result
        }
      }
      return result
    }
    "map" | "filter" | "all" | "some" | "none" | "reduce" => {
      let source = eval(
        arg(values, 0, path),
        data,
        ctx,
        depth + 1,
        child_path(0),
      )
      let scoped = arg(values, 1, path)
      let items = match source {
        Array(xs) => xs
        _ => []
      }
      if op == "reduce" {
        let mut acc = if values.length() > 2 {
          eval(values[2], data, ctx, depth + 1, child_path(2))
        } else {
          Json::null()
        }
        for item in items {
          let scope : Json = { "current": item, "accumulator": acc }
          acc = eval(scoped, scope, ctx, depth + 1, child_path(1))
        }
        return acc
      }
      let output : Array[Json] = []
      for item in items {
        let result = eval(scoped, item, ctx, depth + 1, child_path(1))
        match op {
          "map" => output.push(result)
          "filter" => if truthy(result) { output.push(item) }
          "all" => if !truthy(result) { return false.to_json() }
          "some" => if truthy(result) { return true.to_json() }
          "none" => if truthy(result) { return false.to_json() }
          _ => ()
        }
      }
      return match op {
        "map" | "filter" => output.to_json()
        "all" => (!items.is_empty()).to_json()
        "none" => true.to_json()
        _ => false.to_json()
      }
    }
    _ => ()
  }
  let args : Array[Json] = []
  for i, value in values {
    args.push(eval(value, data, ctx, depth + 1, child_path(i)))
  }
  simple_op(op, args, data, ctx, depth, path)
}

///|
fn simple_op(
  op : String,
  args : Array[Json],
  data : Json,
  ctx : Context,
  depth : Int,
  path : String,
) -> Json raise LogicError {
  match op {
    "var" =>
      read_var(
        data,
        args.get(0).unwrap_or(Json::null()),
        args.get(1).unwrap_or(Json::null()),
        path,
      )
    "!" | "!!" =>
      (if op == "!" {
        !truthy(arg(args, 0, path))
      } else {
        truthy(arg(args, 0, path))
      }).to_json()
    "==" | "!=" | "===" | "!==" => {
      let a = arg(args, 0, path)
      let b = arg(args, 1, path)
      let equal = if op == "===" || op == "!==" {
        strict_equal(a, b)
      } else {
        loose_equal(a, b)
      }
      (if op == "!=" || op == "!==" { !equal } else { equal }).to_json()
    }
    ">" | ">=" | "<" | "<=" => {
      let a = arg(args, 0, path)
      let b = arg(args, 1, path)
      let first = relational(op, a, b)
      (first &&
      (
        args.length() < 3 ||
        op == ">" ||
        op == ">=" ||
        relational(op, b, args[2])
      )).to_json()
    }
    "+" | "*" => {
      if op == "*" && args.is_empty() {
        raise InvalidRule(path, "multiplication requires an argument")
      }
      // JS reduce without an initial value preserves a single * operand's type.
      if op == "*" && args.length() == 1 {
        return args[0]
      }
      let mut result = if op == "+" { 0.0 } else { 1.0 }
      for value in args {
        let n = parse_float(value)
        result = if op == "+" { result + n } else { result * n }
      }
      number_result(result, path)
    }
    "-" | "/" | "%" => {
      let a = numeric(arg(args, 0, path))
      if op == "-" && args.length() == 1 {
        return number_result(-a, path)
      }
      let b = numeric(arg(args, 1, path))
      number_result(
        match op {
          "-" => a - b
          "/" => a / b
          _ => a % b
        },
        path,
      )
    }
    "min" | "max" => {
      if args.is_empty() {
        raise NonFiniteNumber(path)
      }
      let mut result = numeric(args[0])
      for value in args {
        let n = numeric(value)
        if n.is_nan() {
          raise NonFiniteNumber(path)
        }
        if (op == "min" && n < result) || (op == "max" && n > result) {
          result = n
        }
      }
      number_result(result, path)
    }
    "cat" =>
      args
      .map(x => if x == Json::null() { "" } else { js_string(x) })
      .join("")
      .to_json()
    "substr" => {
      let source = js_string(arg(args, 0, path))
      let len = source.length()
      let start_n = numeric(args.get(1).unwrap_or(0))
      let start = clamped_index(start_n, len)
      let end = if args.length() < 3 {
        len
      } else {
        let n = numeric(args[2])
        let available = len - start
        let count = if n < 0.0 { available.to_double() + n } else { n }
        if count.is_nan() || count <= 0.0 {
          start
        } else if count >= available.to_double() {
          len
        } else {
          start + count.to_int()
        }
      }
      string_slice(source, start, end, path)
    }
    "in" => {
      let needle = arg(args, 0, path)
      match arg(args, 1, path) {
        Array(xs) => xs.any(x => strict_equal(x, needle)).to_json()
        String(s) => s.contains(js_string(needle)).to_json()
        _ => false.to_json()
      }
    }
    "merge" => {
      let result : Array[Json] = []
      for value in args {
        match value {
          Array(xs) =>
            for x in xs {
              ctx.visit(depth + 1, path)
              result.push(x)
            }
          _ => {
            ctx.visit(depth + 1, path)
            result.push(value)
          }
        }
      }
      result.to_json()
    }
    "missing" | "missing_some" => {
      let keys = if op == "missing_some" {
        match arg(args, 1, path) {
          Array(xs) => xs
          _ => raise InvalidRule(path, "missing_some requires an array of keys")
        }
      } else {
        match args.get(0) {
          Some(Array(xs)) => xs
          _ => args
        }
      }
      let missing : Array[Json] = []
      for key in keys {
        ctx.visit(depth + 1, path)
        let value = read_var(data, key, Json::null(), path)
        if value == Json::null() || value == "".to_json() {
          missing.push(key)
        }
      }
      if op == "missing_some" &&
        (keys.length() - missing.length()).to_double() >= numeric(args[0]) {
        ([] : Array[Json]).to_json()
      } else {
        missing.to_json()
      }
    }
    "log" => {
      let value = arg(args, 0, path)
      ctx.logs.push(value)
      value
    }
    _ => raise InvalidRule(path, "unrecognized operation: " + op)
  }
}

///|
fn clamped_index(value : Double, len : Int) -> Int {
  if value.is_nan() {
    return 0
  }
  if value < -len.to_double() {
    return 0
  }
  if value > len.to_double() {
    return len
  }
  let n = value.to_int()
  if n < 0 {
    len + n
  } else {
    n
  }
}
