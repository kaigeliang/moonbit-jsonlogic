///|
/// Read a CaseKit v1 transcript. Empty, truncated, unknown-version and duplicate-case documents are errors.
pub fn decode(input : String) -> Suite raise CaseError {
  if input.length() > 2097152 {
    raise Invalid("transcript exceeds 2,097,152 UTF-16 code units")
  }
  let doc = @json.parse(input) catch {
    _ => raise Invalid("invalid JSON transcript")
  }
  match doc {
    Object(fields) => {
      if fields.length() != 3 {
        raise Invalid("expected exactly casekit, suite and cases")
      }
      match (fields.get("casekit"), fields.get("suite"), fields.get("cases")) {
        (Some(Number(version, ..)), Some(String(name)), Some(Array(cases))) => {
          if version != 1.0 {
            raise Invalid("unsupported transcript version")
          }
          if cases.is_empty() {
            raise Invalid("transcript contains no cases")
          }
          let suite = Suite::new(name)
          for record in cases {
            match record {
              Object(record) => {
                if record.length() != 2 {
                  raise Invalid("case must contain exactly id and value")
                }
                match (record.get("id"), record.get("value")) {
                  (Some(String(id)), Some(value)) => suite.observe(id, value)
                  _ => raise Invalid("case requires a string id and a value")
                }
              }
              _ => raise Invalid("case must be an object")
            }
          }
          suite
        }
        _ => raise Invalid("invalid transcript header")
      }
    }
    _ => raise Invalid("transcript must be an object")
  }
}
