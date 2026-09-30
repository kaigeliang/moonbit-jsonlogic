# MoonBit JSONLogic：跨端规则执行与应用接入库

[![Check](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml/badge.svg)](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml)

本项目让应用在 MoonBit 中执行已有的 JSONLogic 业务规则。规则以 JSON 保存和传递，同一份规则可用于动态表单、订单计算、集合筛选和后端条件查询。

仓库源码提供 **JSONLogic 求值库**与 **native QueryX/foxql 适配器**。求值库支持内置操作、短路求值、集合局部作用域、日志捕获、结构化错误和执行预算，并在 native、JavaScript、Wasm、Wasm GC 四后端对照验证。查询模块在明确的字段类型和非空约束下生成现有 QueryX 表达式，复用 foxql 输出参数化 SQL。接入规范见 [查询接入文档](docs/queryx-integration.md)。Mooncakes 已发布的 0.1.0 包含求值库；查询适配器目前通过源码 workspace 使用。

This project executes existing JSONLogic business rules in MoonBit across native, JavaScript, Wasm and Wasm GC targets. The portable runtime supports standard built-in operations with explicit compatibility boundaries, structured errors and execution budgets. A native QueryX/foxql adapter imports typed filter rules into the existing query pipeline and is checked against actual PostgreSQL results. The published 0.1.0 package contains the evaluation core; the query adapter is available from source.

## 目标用户与应用接入

面向使用 JSONLogic 保存业务配置、希望在 MoonBit 中复用规则的应用。开发者可以调用求值 API 实现表单条件、订单计算和集合处理；受约束的筛选规则还可以进入已有的查询生态。

应用流程：

```text
JSONLogic 规则 + JSON 数据
  → MoonBit JSONLogic 求值库
  → 业务结果、日志或结构化错误
```

查询模块面向已有 JSONLogic 筛选规则目录、希望在 MoonBit 后端继续复用配置查询数据库的应用。[React Query Builder](https://react-querybuilder.js.org/docs/utils/export#jsonlogic) 支持生成 JSONLogic，提供可验证的规则来源；它也支持 SQL 等导出格式。数据库接入流程：

```text
存量 JSONLogic 筛选规则 + 服务端字段与类型约束
  → 导入与语义检查
  → QueryX Expr
  → 复用 foxql 生成参数化 SQL
  → 数据库返回匹配记录
```

导入模块对类型不匹配、动态变量和无法保持语义的规则返回 JSON Pointer 与原因。固定 RQB 导出规则在原版 JavaScript、MoonBit JSONLogic、本地 QueryX 和 PostgreSQL 中得到相同的匹配记录 ID；完整求值库的兼容用例另行维护。

## 验证实际接入

需要 MoonBit、Node.js、Python 与 `psql`，以及可连接的 PostgreSQL 服务。查询构建器仅是开发验证依赖。

```sh
moon update
npm ci --prefix tools/queryx-fixtures
node tools/queryx-fixtures/generate.mjs --check
python3 tools/check_queryx.py
```

连接信息使用标准 `PGHOST`、`PGPORT`、`PGUSER`、`PGPASSWORD`、`PGDATABASE` 环境变量；未指定数据库时使用 `postgres`。验证只创建临时表并回滚事务。

- **9 个未修改的 React Query Builder 8.24.3 导出规则，96 次记录求值**：四条执行路径的匹配 ID 一致。
- **18 个规则拒绝与 8 个输入拒绝用例**：验证错误种类、规则／数据位置和原因。
- **负向验证**：故意修改 SQL 参数，确认实际数据库结果差异会被发现。
- **16 项适配器单元测试**：包含反向比较、严格区间边界、Int32 范围和输入预算。

每次运行在 `output/queryx/` 保存规则来源、SQL、类型化参数、逐项结果、拒绝诊断和负控报告。当前验证使用 PostgreSQL 17；数据集与支持范围见 [接入文档](docs/queryx-integration.md)。

## 项目范围

| 部分 | 用途 |
| --- | --- |
| `src/` | JSONLogic 求值库；供应用安装与调用 |
| `src/queryx/` | native JSONLogic 筛选规则导入与记录校验 |
| `src/examples/queryx/` | 调用实际 QueryX/foxql 的 native 接入程序 |
| `compat/`、`tools/`、`tests/` | 与原版 JavaScript 对照的回归验证；不进入应用运行路径 |
| `docs/queryx-integration.md` | 查询接入约定、复现方法和扩展范围 |

JSONLogic 核心包与 `compat` 对照程序只导入 MoonBit 标准库。查询适配包依赖 QueryX 0.2.1／foxql 0.1.3，仅支持 native。根模块固定 `moonbitlang/x@0.5.5` 以兼容当前编译器；适配器不修改下载的依赖源码。Python、Node.js 和 PostgreSQL 用于接入验证。

### 与相邻工具的边界

| 工具 | 已有能力 | 本项目的补充方向 |
| --- | --- | --- |
| [QueryX](https://github.com/jaredzhou/moonbase/blob/main/queryx/README.mbt.md) | 自定义 JSON 筛选格式、表达式求值、字段解析和 foxql 桥接 | 将标准 JSONLogic 的受约束筛选子集导入其现有 `Expr` |
| [foxql](https://github.com/jaredzhou/moonbase/tree/main/foxql) | SQL 查询构建 | 复用其 SQL 输出，提供 JSONLogic 导入与语义拒绝报告 |
| [mbel](https://github.com/dimon-83/mbel)、moon_cel 等表达式库 | 使用其他表达式或规则标准，具备相似的规则求值用途 | 直接接受 JSONLogic 规则对象，按其 truthiness、类型转换、短路和集合作用域执行，并给出固定版本语义对照 |
| [json-logic-js](https://github.com/jwadhams/json-logic-js) | 在 JavaScript 中执行 JSONLogic | 已实现 MoonBit 求值与固定版本对照，并作为查询接入的独立参考 |

项目以 JSONLogic 规则格式和执行语义为兼容目标；相似表达式工具之间仍有应用场景交集。查询模块负责有类型约束和语义拒绝的 JSONLogic 导入，字段解析与 SQL 查询构建复用 QueryX/foxql。求值库的 [兼容范围](docs/compatibility.md)与查询适配范围分别记录。

## JSONLogic：可传递的业务规则

```json
{"and": [
  {">=": [{"var": "age"}, 18]},
  {"==": [{"var": "country"}, "CN"]}
]}
```

这份规则搭配 `{"age": 22, "country": "CN"}` 得到 `true`。规则可存入配置、经 API 传递，再由不同端执行；无需为每条业务规则生成一段源代码。

## 接入验证场景

- **用户人群筛选**：导入年龄、状态和启用条件，通过现有查询管线返回匹配用户 ID。
- **订单记录查询**：导入状态与金额条件，复用字段映射并核对四条执行路径的匹配订单 ID。
- **导入阻塞报告**：遇到隐式类型转换、动态变量或集合规则，报告 JSON Pointer 和拒绝原因，保留原始配置以便修订。

接入限定顶层非空 Int32／字符串／布尔字段。Int32 支持比较，字符串和布尔值支持同类型相等／不等；逻辑组合非空且各叶节点均为比较。缺失值、NULL、类型转换、动态路径、默认值、集合和字符串排序均拒绝。PostgreSQL 文本列使用 `COLLATE "C"`，SQL 类型与字段声明一致。

## JSONLogic 求值库：快速运行

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

示例代码：[表单](src/examples/form/main.mbt) · [订单](src/examples/order/main.mbt) · [集合筛选](src/examples/filter/main.mbt)。每个示例均断言预期结果；查询接入由独立的 [native 程序](src/examples/queryx/main.mbt)与上述 PostgreSQL 验证命令演示。

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
src/queryx/           native 筛选规则接入适配器与单元测试
src/examples/         基础求值示例与 native 查询接入程序
compat/               跨实现、跨后端的验证程序
tests/                边界输入 fixtures
tools/                原版执行器、fixture 生成器、兼容性检查
third_party/          固定版本的原版 JS、官方测试与许可证
docs/                 基础 API、兼容性说明与查询接入约定
```

修改 fixtures 后执行 `python3 tools/generate_cases.py && moon fmt`。CI 会检查 fixtures、公共 API、各后端单元测试、示例、兼容结果及比较器失败路径。

## 后续开发方向

以下内容尚未交付，验收以可运行接口、真实应用接入和独立结果对照为准：

1. **JavaScript／Wasm GC SDK 与表单接入**：提供 JSON 输入输出接口、加载器和类型声明。接入 Form.io 的标准 JSONLogic 条件、计算值与验证配置，实际操作表单并与原求值器、native 求值结果对照。框架自定义操作必须单独声明支持范围；Form.io 官方 [条件与验证文档](https://help.form.io/form-building/logic-and-conditions) 和 [计算值示例](https://formio.github.io/formio.js/app/examples/calculated.html) 提供配置来源。
2. **规则分析与部署诊断**：在执行前报告操作、数据路径、动态依赖和规则位置，区分顶层数据、集合元素与 reduce 的作用域。分析结果用于导入检查和接入配置诊断；执行预算继续由求值器执行。
3. **规则集批量执行**：提供带规则 ID 的批量 API 和 native CLI，逐条输出结果、日志、诊断与资源消耗，并限制单条与整批执行预算。用于复核已有规则目录和后端批处理。

兼容性比较、fixtures 和报告脚本作为上述功能的开发验证工具。新增功能完成各自的实现与验证后形成真实开发提交。

## 许可证与来源

JSONLogic 采用 MIT 许可证。

- **JSONLogic**：MoonBit 移植参考 Jeremy Wadhams 的 `json-logic-js`；标准规则格式及原版操作语义归于上游。原版代码和官方测试保留 MIT 许可证；固定提交、文件校验值及来源见 [来源记录](third_party/json-logic-js/README.md)。
- **查询生态**：QueryX 0.2.1 和 foxql 0.1.3 来自 Jared Zhou 的 [moonbase](https://github.com/jaredzhou/moonbase)，采用 Apache-2.0；其表达式与 SQL 桥接能力归于上游。React Query Builder 8.24.3 仅用于产生开发 fixtures，来源与版本记录在 fixture 和 npm 锁文件中。
