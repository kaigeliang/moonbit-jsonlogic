///|
fn show_value(value : Json?) -> String {
  match value {
    None => "<missing>"
    Some(v) => canonical_unchecked(v)
  }
}

///|
fn kind_label(kind : DifferenceKind) -> String {
  match kind {
    MissingCase => "missing case"
    ExtraCase => "extra case"
    ValueMismatch => "value mismatch"
    TypeMismatch => "type mismatch"
    MissingField => "missing field"
    ExtraField => "extra field"
  }
}

///|
/// Human-readable summary. Values and IDs are JSON escaped, keeping each diagnostic on one line.
pub fn Report::render(
  self : Report,
  max_differences? : Int = 20,
) -> String raise CaseError {
  if max_differences < 0 {
    raise Invalid("max_differences must be nonnegative")
  }
  let status = if self.is_match() { "MATCH" } else { "DIFFERENT" }
  let lines = [
    "\{status} \{self.suite.to_json().stringify()}: \{self.matched_cases}/\{self.total_cases} cases match; \{self.differences.length()} differences",
  ]
  if self.abs_tol > 0.0 || self.rel_tol > 0.0 {
    lines.push(
      "numeric tolerance: absolute=\{self.abs_tol}, relative=\{self.rel_tol}",
    )
  }
  for i, diff in self.differences {
    if i >= max_differences {
      break
    }
    lines.push(
      "  \{diff.case_id.to_json().stringify()} at \{diff.path.to_json().stringify()}: \{kind_label(diff.kind)}",
    )
    lines.push("    expected: \{show_value(diff.expected)}")
    lines.push("    actual:   \{show_value(diff.actual)}")
  }
  if self.differences.length() > max_differences {
    lines.push(
      "  ... \{self.differences.length() - max_differences} more differences",
    )
  }
  lines.join("\n")
}

///|
/// Machine-readable report with stable field ordering.
pub fn Report::encode(self : Report) -> String raise CaseError {
  canonical(self.to_json())
}
