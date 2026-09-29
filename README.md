# MoonBit JSONLogic

[![Check](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml/badge.svg)](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml)

用 MoonBit 执行 JSONLogic 规则，并用固定版本的原版 JavaScript 测试其跨后端行为。

This repository's product is a MoonBit implementation of the standard [JSONLogic](https://jsonlogic.com/) operators. It is tested against `json-logic-js` 2.0.5 on native, JavaScript, Wasm and Wasm GC.

## 项目范围

| 部分 | 用途 |
| --- | --- |
| `src/` | JSONLogic 运行库；供应用安装与调用 |
| `compat/`、`tools/`、`tests/` | 与原版 JavaScript 对照的回归验证；不进入应用运行路径 |
| `support/casekit/` | 为使仓库内的对照验证可复现而保留的测试工具源码；独立项目见 [moonbit-casekit](https://github.com/kaigeliang/moonbit-casekit) |

JSONLogic 运行库只依赖 MoonBit 标准库。应用使用 JSONLogic 时无需安装或导入 CaseKit；`compat` 模块在开发时使用 CaseKit 比较原版 JavaScript 与 MoonBit 的输出。本仓库的项目范围是 JSONLogic，不把 CaseKit 的独立功能计入本库的运行能力。

### 与相邻工具的边界

| 工具 | 主要用途 | 本项目提供的能力 |
| --- | --- | --- |
| MoonBit 标准库的 `Json` | 表示、解析和序列化 JSON 值 | 求值 JSONLogic 规则，包括变量、条件、计算和集合操作 |
| [moonschema](https://mooncakes.io/docs/moonbitstack/moonschema) 等 JSON Schema 验证库 | 验证数据是否符合 schema | 让规则根据数据计算结果；它不替代 schema 验证 |
| [json-logic-js](https://github.com/jwadhams/json-logic-js) | 在 JavaScript 中执行 JSONLogic | 在 MoonBit 的 native、JS、Wasm 和 Wasm GC 后端执行同一种规则格式，并对照固定版本的原版测试 |

这是对已有 JSONLogic 格式的 MoonBit 移植和兼容性工作，不主张发明新规则格式，也不声称所有 JavaScript 边界行为完全相同。[兼容范围](docs/compatibility.md)列出已验证行为与已知差异。

## JSONLogic：可传递的业务规则

```json
{"and": [
  {">=": [{"var": "age"}, 18]},
  {"==": [{"var": "country"}, "CN"]}
]}
```

这份规则搭配 `{"age": 22, "country": "CN"}` 得到 `true`。规则可存入配置、经 API 传递，再由不同端执行；无需为每条业务规则生成一段源代码。

## 适用场景

- **动态表单**：控制字段显示，判断必填项，检查多个联系方式至少填一个。
- **业务配置**：根据会员状态、订单金额或权限数据计算条件结果。
- **数据处理**：使用 `filter`、`map`、`reduce` 从 JSON 集合筛选、映射和汇总。

JSONLogic 已用于 [Form.io 的条件与校验](https://help.form.io/form-building/logic-and-conditions)。本库提供 MoonBit 执行端；尚未与 Form.io 应用做端到端集成。

## 快速运行

需要 MoonBit 工具链；兼容性验证另需 Node.js 22+ 和 Python 3.10+。已验证的工具链为 MoonBit CLI `0.1.20260920` / moonc `v0.10.14+7d59c7ec9`。

```sh
git clone https://github.com/kaigeliang/moonbit-jsonlogic.git
cd moonbit-jsonlogic
moon update
moon run src/examples/form --target native
moon run src/examples/order --target js
moon run src/examples/filter --target wasm-gc
```

三个示例分别输出：

```json
{"show_company":true,"missing_required":["company"]}
{"subtotal":110,"discount_percent":10}
["Ming"]
```

示例代码：[表单](src/examples/form/main.mbt) · [订单](src/examples/order/main.mbt) · [集合筛选](src/examples/filter/main.mbt)。每个示例均断言预期结果。

## 在你的 MoonBit 项目中使用

版本 0.1.0 已发布到 [Mooncakes](https://mooncakes.io/docs/kaigeliang/jsonlogic)。在你的 MoonBit 项目中运行：

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

兼容性脚本执行固定版本的原版 JavaScript，再用 **CaseKit** 将每个 MoonBit 后端的结果与原版逐项比较：

- 278 个官方用例 + 37 个边界用例，当前共 **315 个**。
- 四个后端均使用同一组输入，采用严格比较，不启用数值容差。
- 每次运行保存输入版本对应的观察结果与差异报告到 `output/compat/`。
- 故意篡改一个结果的负向验证，确认比较器会拒绝错误输出。

JSONLogic 的 14 项求值与错误行为单元测试在四个后端运行；测试工具另有采集、比较及失败路径测试。外部应用接入测试验证 JSONLogic 可以独立使用。

## 仓库内容

```text
src/                  JSONLogic 运行库与单元测试
src/examples/         可运行的使用示例
compat/               跨实现、跨后端的验证程序
tests/                边界输入 fixtures
tools/                原版执行器、fixture 生成器、兼容性检查
support/casekit/      供本仓库回归验证使用的 CaseKit 源码副本
third_party/          固定版本的原版 JS、官方测试与许可证
docs/                 API 与兼容性说明
```

修改 fixtures 后执行 `python3 tools/generate_cases.py && moon fmt`。CI 会检查 fixtures、公共 API、各后端单元测试、示例、兼容结果及 CaseKit 失败路径。

## 许可证与来源

JSONLogic 采用 MIT 许可证。

- **JSONLogic**：MoonBit 移植参考 Jeremy Wadhams 的 `json-logic-js`；标准规则格式及原版操作语义归于上游。原版代码和官方测试保留 MIT 许可证；固定提交、文件校验值及来源见 [来源记录](third_party/json-logic-js/README.md)。
- **测试工具**：`support/casekit/` 保留 CaseKit 的 MIT 许可证；其独立仓库和使用文档见 [moonbit-casekit](https://github.com/kaigeliang/moonbit-casekit)。
