# MoonBit JSONLogic：存量筛选规则接入适配库

[![Check](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml/badge.svg)](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml)

本项目面向已保存的 JSONLogic 筛选配置，定位为 MoonBit 的 QueryX/foxql 接入适配库。

**实现状态：已交付 JSONLogic 基础求值库；QueryX/foxql 适配器尚未实现。** 0.1.0、下方安装方式、示例与兼容性结果均对应基础求值库。接入范围和交付条件见 [接入规范与实施计划](docs/queryx-integration.md)。

This project targets importing existing JSONLogic filter rules into MoonBit's QueryX/foxql query pipeline. The current release contains the JSONLogic evaluation core, tested against `json-logic-js` 2.0.5 on native, JavaScript, Wasm and Wasm GC. The query adapter is planned and is not available in 0.1.0.

## 目标用户与接入流程

面向已有 JSONLogic 筛选规则目录、希望在 MoonBit 后端继续复用配置查询数据库的应用。[React Query Builder](https://react-querybuilder.js.org/docs/utils/export#jsonlogic) 支持生成 JSONLogic，提供可验证的规则来源；它也支持 SQL 等导出格式。本项目的目标输入是已经保存为 JSONLogic 的配置。

计划流程：

```text
存量 JSONLogic 筛选规则 + 服务端字段与类型约束
  → 导入与语义检查
  → QueryX Expr
  → 复用 foxql 生成参数化 SQL
  → 数据库返回匹配记录
```

计划新增有明确支持范围的 JSONLogic 导入模块：对类型不匹配、动态变量和无法保持语义的规则返回位置与原因。验收时比较原 JSONLogic、本地 QueryX 和实际数据库返回的记录 ID。当前求值测试尚不能证明这条接入流程成立。

## 项目范围

| 部分 | 用途 |
| --- | --- |
| `src/` | 已实现的 JSONLogic 基础求值库；供应用安装与调用 |
| `compat/`、`tools/`、`tests/` | 与原版 JavaScript 对照的回归验证；不进入应用运行路径 |
| `docs/queryx-integration.md` | QueryX/foxql 接入设计与待实现清单 |

JSONLogic 运行库与 `compat` 对照程序只依赖 MoonBit 标准库。开发时由 Python 脚本逐项比较原版 JavaScript 与 MoonBit 的输出；Python 和 Node.js 仅用于回归验证。

### 与相邻工具的边界

| 工具 | 已有能力 | 本项目的补充方向 |
| --- | --- | --- |
| [QueryX](https://github.com/jaredzhou/moonbase/blob/main/queryx/README.mbt.md) | 自定义 JSON 筛选格式、表达式求值、字段解析和 foxql 桥接 | 计划将标准 JSONLogic 的受约束筛选子集导入其现有 `Expr` |
| [foxql](https://github.com/jaredzhou/foxql) | SQL 查询构建 | 计划复用其 SQL 输出，提供 JSONLogic 导入与语义拒绝报告 |
| [mbel](https://github.com/dimon-83/mbel) | 文本表达式、解释器与 VM、静态检查、执行预算 | 本项目聚焦存量 JSONLogic 筛选配置接入查询管线 |
| [json-logic-js](https://github.com/jwadhams/json-logic-js) | 在 JavaScript 中执行 JSONLogic | 已实现 MoonBit 求值与固定版本对照；计划用作接入一致性验证的一方 |

接入模块负责有类型约束和语义拒绝的 JSONLogic 导入，字段解析与 SQL 查询构建复用 QueryX/foxql。基础库的 [兼容范围](docs/compatibility.md)与查询适配范围分别记录。

## JSONLogic：可传递的业务规则

```json
{"and": [
  {">=": [{"var": "age"}, 18]},
  {"==": [{"var": "country"}, "CN"]}
]}
```

这份规则搭配 `{"age": 22, "country": "CN"}` 得到 `true`。规则可存入配置、经 API 传递，再由不同端执行；无需为每条业务规则生成一段源代码。

## 计划接入的验证场景（尚未实现）

- **用户人群筛选**：导入已经保存的年龄、状态条件，通过现有查询管线返回匹配用户 ID。
- **订单记录查询**：导入状态与金额条件，复用字段映射并核对三种执行路径的匹配订单 ID。
- **导入阻塞报告**：遇到隐式类型转换、动态变量或集合规则，报告 JSON Pointer 和拒绝原因，保留原始配置以便修订。

第一版拟限定类型明确、非空字段的同类型比较和纯布尔组合。缺失值、SQL NULL、字符串排序与 `and`/`or` 返回值等差异必须逐项验证；不能机械翻译所有 JSONLogic 操作。完整接入验证前，不声明数据库筛选兼容。

## 已实现的基础求值库：快速运行

需要 MoonBit 工具链；兼容性验证另需 Node.js 22+ 和 Python 3.10+。已验证的工具链为 MoonBit CLI `0.1.20260920` / moonc `v0.10.14+7d59c7ec9`。

```sh
git clone https://github.com/kaigeliang/moonbit-jsonlogic.git
cd moonbit-jsonlogic
moon update
moon run src/examples/form --target native
moon run src/examples/order --target js
moon run src/examples/filter --target wasm-gc
```

三个基础求值示例分别输出：

```json
{"show_company":true,"missing_required":["company"]}
{"subtotal":110,"discount_percent":10}
["Ming"]
```

示例代码：[表单](src/examples/form/main.mbt) · [订单](src/examples/order/main.mbt) · [集合筛选](src/examples/filter/main.mbt)。每个示例均断言预期结果；它们验证求值能力，尚未接入 QueryX/foxql 或数据库。

## 在你的 MoonBit 项目中使用

基础求值库 0.1.0 已发布到 [Mooncakes](https://mooncakes.io/docs/kaigeliang/jsonlogic)，不包含 QueryX/foxql 适配器。在你的 MoonBit 项目中运行：

```sh
moon add kaigeliang/jsonlogic@0.1.0
```

也可以通过源码 workspace 使用。例如把本仓库和你的 `app` 放在同一父目录，在 `app/moon.mod` 中加入：

```moonbit
import { "kaigeliang/jsonlogic@0.1.0" }
```

在 `app/moon.work` 中加入两个成员：

```moonbit
members = [".", "../moonbit-jsonlogic"]
```

在调用包的 `moon.pkg` 中导入：

```moonbit
import { "kaigeliang/jsonlogic" @logic }
```

```moonbit
fn main raise {
  let rule : Json = { ">=": [{ "var": "age" }, 18] }
  let result = @logic.apply(rule, { "age": 22 })
  assert_eq(result, true)
}
```

`apply_json(rule_text, data_text)` 接受两个 JSON 文本；`evaluate(rule, data, max_steps=..., max_depth=...)` 返回结果、捕获的 `log` 内容与已消耗步数。详见 [API 与集成说明](docs/api.md)。

## 支持的操作

| 类别 | 操作 |
| --- | --- |
| 数据 | `var`、`missing`、`missing_some` |
| 条件 | `if`、`?:`、`and`、`or`、`!`、`!!` |
| 比较 | `==`、`!=`、`===`、`!==`、`>`、`>=`、`<`、`<=` |
| 数值 | `+`、`-`、`*`、`/`、`%`、`min`、`max` |
| 字符串与集合 | `cat`、`substr`、`in`、`merge`、`map`、`filter`、`reduce`、`all`、`some`、`none` |
| 调试 | `log`（捕获到返回值） |

遵循 JSONLogic 的空数组假值、短路求值、集合局部作用域和 JavaScript 风格类型转换。非有限数、JavaScript 原型属性和自定义操作等边界见 [兼容范围](docs/compatibility.md)。通过已有用例不代表覆盖了所有 JavaScript 行为。

## 兼容性验证

```sh
moon test --target native
python3 tools/check_compat.py
```

兼容性脚本执行固定版本的原版 JavaScript，将每个 MoonBit 后端的结果与原版逐项比较：

- 278 个官方用例 + 37 个边界用例，当前共 **315 个**。
- 四个后端均使用同一组输入，采用严格比较，不启用数值容差。
- 每次运行保存输入版本对应的观察结果与差异报告到 `output/compat/`。
- 故意篡改一个结果的负向验证，确认比较器会拒绝错误输出。

JSONLogic 的 14 项求值与错误行为单元测试在四个后端运行；Python 测试检查比较器会拒绝类型差异、缺失结果和无效输入。外部应用接入测试验证独立应用能够调用本库。

## 仓库内容

```text
src/                  JSONLogic 运行库与单元测试
src/examples/         可运行的使用示例
compat/               跨实现、跨后端的验证程序
tests/                边界输入 fixtures
tools/                原版执行器、fixture 生成器、兼容性检查
third_party/          固定版本的原版 JS、官方测试与许可证
docs/                 基础 API、兼容性说明与查询接入计划
```

修改 fixtures 后执行 `python3 tools/generate_cases.py && moon fmt`。CI 会检查 fixtures、公共 API、各后端单元测试、示例、兼容结果及比较器失败路径。

## 许可证与来源

JSONLogic 采用 MIT 许可证。

- **JSONLogic**：MoonBit 移植参考 Jeremy Wadhams 的 `json-logic-js`；标准规则格式及原版操作语义归于上游。原版代码和官方测试保留 MIT 许可证；固定提交、文件校验值及来源见 [来源记录](third_party/json-logic-js/README.md)。
