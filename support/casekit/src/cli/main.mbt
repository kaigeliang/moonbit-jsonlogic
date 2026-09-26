///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  try {
    let args = @env.args()
    let paths : Array[String] = []
    let mut json_output = false
    let mut abs_tol = 0.0
    let mut rel_tol = 0.0
    let mut i = 1
    while i < args.length() {
      match args[i] {
        "--help" | "-h" => {
          @stdio.stdout.write(
            "Usage: casekit [--json] [--abs-tol N] [--rel-tol N] EXPECTED ACTUAL\nExit codes: 0 match, 1 difference, 2 invalid input or execution error.\n",
          )
          return
        }
        "--json" => json_output = true
        "--abs-tol" | "--rel-tol" as option => {
          i += 1
          if i >= args.length() {
            fail("missing value for \{option}")
          }
          let value = match @json.parse(args[i]) {
            Number(n, ..) => n
            _ => fail("tolerance must be a number")
          }
          if option == "--abs-tol" {
            abs_tol = value
          } else {
            rel_tol = value
          }
        }
        value => {
          if value.has_prefix("--") {
            fail("unknown option: \{value}")
          }
          paths.push(value)
        }
      }
      i += 1
    }
    if paths.length() != 2 {
      fail("expected two transcript paths; use --help")
    }
    let expected = @casekit.decode(@fs.read_file(paths[0]).text())
    let actual = @casekit.decode(@fs.read_file(paths[1]).text())
    let report = @casekit.compare(expected, actual, abs_tol~, rel_tol~)
    @stdio.stdout.write(
      (if json_output { report.encode() } else { report.render() }) + "\n",
    )
    if !report.is_match() {
      exit(1)
    }
  } catch {
    error => {
      let message = match error {
        @casekit.Invalid(message) => message
        _ => error.to_string()
      }
      @stdio.stderr.write("casekit: " + message + "\n")
      exit(2)
    }
  }
}
