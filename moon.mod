name = "kaigeliang/jsonlogic"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/kaigeliang/moonbit-jsonlogic"

license = "MIT"

keywords = [ "jsonlogic", "rules", "interpreter", "queryx" ]

description = "Portable JSONLogic rule evaluation with native QueryX/foxql integration"

source = "src"

preferred_target = "native"

import {
  "jaredzhou/queryx@0.2.1",
  "jaredzhou/foxql@0.1.3",
  "moonbitlang/x@0.5.5",
}
