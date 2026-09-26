// JSONLogic coercion follows json-logic-js 2.0.5 for JSON values.

///|
fn js_string(value : Json) -> String {
  match value {
    Null => "null"
    True => "true"
    False => "false"
    String(s) => s
    Number(n, ..) => if n == 0.0 { "0" } else { n.to_string() }
    Array(xs) =>
      xs.map(x => if x == Json::null() { "" } else { js_string(x) }).join(",")
    Object(_) => "[object Object]"
  }
}

///|
fn parse_number(text : String) -> Double {
  let s = js_trim(text)
  if s.is_empty() {
    return 0.0
  }
  if s == "Infinity" || s == "+Infinity" {
    return @double.infinity
  }
  if s == "-Infinity" {
    return @double.neg_infinity
  }
  // Number accepts unsigned 0x/0b/0o strings; arithmetic + and * use parseFloat instead.
  if s.has_prefix("0x") ||
    s.has_prefix("0X") ||
    s.has_prefix("0b") ||
    s.has_prefix("0B") ||
    s.has_prefix("0o") ||
    s.has_prefix("0O") {
    let base = if s[1] == 120 || s[1] == 88 {
      16
    } else if s[1] == 98 || s[1] == 66 {
      2
    } else {
      8
    }
    if s.length() == 2 {
      return @double.not_a_number
    }
    let mut result = 0.0
    for i = 2; i < s.length(); i = i + 1 {
      let c = s[i].to_int()
      let digit = if c >= 48 && c <= 57 {
        c - 48
      } else if c >= 65 && c <= 70 {
        c - 55
      } else if c >= 97 && c <= 102 {
        c - 87
      } else {
        -1
      }
      if digit < 0 || digit >= base {
        return @double.not_a_number
      }
      result = result * base.to_double() + digit.to_double()
    }
    return result
  }
  // Restrict decimal syntax before delegating conversion to the standard library.
  let end = float_prefix_end(s)
  if end != s.length() || end == 0 {
    return @double.not_a_number
  }
  @string.parse_double(s) catch {
    _ => @double.not_a_number
  }
}

///|
fn numeric(value : Json) -> Double {
  match value {
    Null | False => 0.0
    True => 1.0
    Number(n, ..) => n
    _ => parse_number(js_string(value))
  }
}

///|
fn digit_at(s : String, i : Int) -> Bool {
  i < s.length() && s[i] >= 48 && s[i] <= 57
}

///|
fn float_prefix_end(s : String) -> Int {
  let mut i = 0
  if i < s.length() && (s[i] == 43 || s[i] == 45) {
    i += 1
  }
  let begin = i
  while digit_at(s, i) {
    i += 1
  }
  let mut digits = i - begin
  if i < s.length() && s[i] == 46 {
    i += 1
    let begin = i
    while digit_at(s, i) {
      i += 1
    }
    digits += i - begin
  }
  if digits == 0 {
    return 0
  }
  let before_exp = i
  if i < s.length() && (s[i] == 69 || s[i] == 101) {
    i += 1
    if i < s.length() && (s[i] == 43 || s[i] == 45) {
      i += 1
    }
    let begin = i
    while digit_at(s, i) {
      i += 1
    }
    if i == begin {
      return before_exp
    }
  }
  i
}

///|
fn parse_float(value : Json) -> Double {
  let s = js_trim(js_string(value))
  if s.has_prefix("Infinity") || s.has_prefix("+Infinity") {
    return @double.infinity
  }
  if s.has_prefix("-Infinity") {
    return @double.neg_infinity
  }
  let end = float_prefix_end(s)
  if end == 0 {
    return @double.not_a_number
  }
  @string.parse_double(s[:end]) catch {
    _ => @double.not_a_number
  }
}

///|
fn strict_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Array(x), Array(y)) => physical_equal(x, y)
    (Object(x), Object(y)) => physical_equal(x, y)
    (Number(x, ..), Number(y, ..)) => x == y
    _ => a == b
  }
}

///|
fn loose_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Array(_), Array(_)) | (Object(_), Object(_)) => strict_equal(a, b)
    (Array(_), Object(_)) | (Object(_), Array(_)) => false
    (True, _) | (False, _) => loose_equal(numeric(a).to_json(), b)
    (_, True) | (_, False) => loose_equal(a, numeric(b).to_json())
    (Number(x, ..), String(_)) => x == numeric(b)
    (String(_), Number(y, ..)) => numeric(a) == y
    (Number(_, ..), Array(_))
    | (Number(_, ..), Object(_))
    | (String(_), Array(_))
    | (String(_), Object(_)) => loose_equal(a, js_string(b).to_json())
    (Array(_), Number(_, ..))
    | (Object(_), Number(_, ..))
    | (Array(_), String(_))
    | (Object(_), String(_)) => loose_equal(js_string(a).to_json(), b)
    _ => strict_equal(a, b)
  }
}

///|
fn relational(op : String, a : Json, b : Json) -> Bool {
  let a = match a {
    Array(_) | Object(_) => js_string(a).to_json()
    _ => a
  }
  let b = match b {
    Array(_) | Object(_) => js_string(b).to_json()
    _ => b
  }
  match (a, b) {
    (String(x), String(y)) => {
      let c = x.lexical_compare(y)
      match op {
        ">" => c > 0
        ">=" => c >= 0
        "<" => c < 0
        _ => c <= 0
      }
    }
    _ => {
      let x = numeric(a)
      let y = numeric(b)
      match op {
        ">" => x > y
        ">=" => x >= y
        "<" => x < y
        _ => x <= y
      }
    }
  }
}

// ECMAScript WhiteSpace and LineTerminator, excluding Unicode NEL (U+0085).

///|
fn js_space(c : UInt16) -> Bool {
  (c >= 9 && c <= 13) ||
  c == 32 ||
  c == 160 ||
  c == 5760 ||
  (c >= 8192 && c <= 8202) ||
  c == 8232 ||
  c == 8233 ||
  c == 8239 ||
  c == 8287 ||
  c == 12288 ||
  c == 65279
}

///|
fn js_trim(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && js_space(s[start]) {
    start += 1
  }
  while end > start && js_space(s[end - 1]) {
    end -= 1
  }
  s[start:end].to_owned()
}
