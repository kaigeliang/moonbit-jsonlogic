# MoonBit JSONLogic

[![Check](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml/badge.svg)](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml)

**在 MoonBit 中执行 JSONLogic 规则，让表单条件、业务判断和数据筛选复用同一份 JSON。**

A pure MoonBit implementation of the standard [JSONLogic](https://jsonlogic.com/) operators, checked against `json-logic-js` 2.0.5 on native, JavaScript, Wasm and Wasm GC. The runtime depends only on MoonBit's core library.

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

当前通过源码 workspace 使用，**尚未发布到 Mooncakes**。例如把本仓库和你的 `app` 放在同一父目录，在 `app/moon.mod` 中加入：

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

## 验证与 CaseKit

```sh
moon test --target native
python3 tools/check_compat.py
```

兼容性脚本执行固定版本的原版 JavaScript，再用 **CaseKit** 将每个 MoonBit 后端的结果与原版逐项比较：

- 278 个官方用例 + 37 个边界用例，当前共 **315 个**。
- 四个后端均使用同一组输入，采用严格比较，不启用数值容差。
- 每次运行保存输入版本对应的观察结果与差异报告到 `output/compat/`。
- 故意篡改一个结果的负向验证，确认比较器会拒绝错误输出。

[CaseKit](support/casekit/README.md) 是仓库内独立的测试组件，负责观察记录和 JSON Pointer 差异定位。它仅被 `compat` 验证模块依赖，**应用使用 JSONLogic 主库时无需依赖 CaseKit**。原有 CaseKit 历史与独立 API 保留。

## 仓库内容

```text
src/                  JSONLogic 运行库与单元测试
src/examples/         可运行的使用示例
compat/               跨实现、跨后端的验证程序
tests/                边界输入 fixtures
tools/                原版执行器、fixture 生成器、兼容性检查
support/casekit/      独立的差异比较组件
third_party/          固定版本的原版 JS、官方测试与许可证
docs/                 API 与兼容性说明
```

修改 fixtures 后执行 `python3 tools/generate_cases.py && moon fmt`。CI 会检查 fixtures、公共 API、各后端单元测试、示例、兼容结果及 CaseKit 失败路径。

## 许可证与来源

MIT。MoonBit 移植参考 Jeremy Wadhams 的 `json-logic-js`；原版代码和官方测试均保留 MIT 许可证。固定提交、文件校验值及来源见 [third_party/json-logic-js/README.md](third_party/json-logic-js/README.md)。
