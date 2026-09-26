# MoonBit JSONLogic & CaseKit

[![Check](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml/badge.svg)](https://github.com/kaigeliang/moonbit-jsonlogic/actions/workflows/check.yml)

**用 JSONLogic 复用跨端业务规则，用自主开发的 CaseKit 检查跨实现、跨后端的行为一致性。**

Two independently usable MoonBit libraries: a port of the standard [JSONLogic](https://jsonlogic.com/) operators, and **CaseKit**, our original cross-backend behavior testing library. CaseKit checks the port against `json-logic-js` 2.0.5 on native, JavaScript, Wasm and Wasm GC.

## 两个可独立使用的库

| 库 | 本项目的工作 | 使用者得到什么 |
| --- | --- | --- |
| **JSONLogic** | 将 `json-logic-js` 的标准操作语义移植到 MoonBit，增加结构化错误、执行限制与兼容性回归用例 | 在不同目标平台执行同一份表单、业务和数据处理规则 |
| **CaseKit** | 自主设计并实现观察值采集、版本化结果协议、结构化比较、差异报告、CLI 和多后端运行器 | 为自己的库记录行为、比较结果、定位差异，并接入 CI |

JSONLogic 求值核心与 CaseKit 比较核心均只依赖 MoonBit 标准库。两者独立接入：应用可只使用 JSONLogic；其他库作者可单独使用 CaseKit。仓库内的 `compat` 模块将两者连接，提供原版 JavaScript 到各 MoonBit 后端的对照验证。

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

## CaseKit：自主开发的一致性测试库

CaseKit 面向移植库、跨平台库及工具链升级的维护者。它把记录输出、验证结果文件、比较差异和处理 CI 状态封装成可复用 API 与工具：

- **观察采集**：以稳定用例编号记录 JSON 值，保存深拷贝快照，避免后续修改污染结果。
- **结果协议**：校验版本、编号和结构，拒绝空结果、重复用例及无效数值。
- **结构化比较**：按用例编号比较，区分缺失、`null`、类型和数组顺序变化，使用 JSON Pointer 定位嵌套差异。
- **数值控制**：默认严格比较；需要时显式设置绝对或相对容差。
- **报告与自动化**：输出文本或 JSON 报告；CLI 与运行器区分一致、存在差异和执行失败，并保存可复查结果。

可用于文本/序列化、数值计算、算法与数据结构等库；JSONLogic 是当前仓库中完整接入该测试库的应用。从仓库根目录运行：

```sh
# CaseKit 自身的 Unicode/JSON 跨后端示例
python3 support/casekit/tools/check_targets.py

# 查看人为构造的差异及其定位报告
moon run support/casekit/src/examples/canary --target native
```

接入其他项目、比较已有结果和协议细节见 [CaseKit 使用文档](support/casekit/README.md)。

## 两个库如何一起验证

```sh
moon test --target native
python3 tools/check_compat.py
```

兼容性脚本执行固定版本的原版 JavaScript，再用 **CaseKit** 将每个 MoonBit 后端的结果与原版逐项比较：

- 278 个官方用例 + 37 个边界用例，当前共 **315 个**。
- 四个后端均使用同一组输入，采用严格比较，不启用数值容差。
- 每次运行保存输入版本对应的观察结果与差异报告到 `output/compat/`。
- 故意篡改一个结果的负向验证，确认比较器会拒绝错误输出。

单元测试分别覆盖 JSONLogic 的 14 项求值与错误行为、CaseKit 的 18 项采集与比较行为，四个后端各运行 32 项；另有 8 项 CLI／运行器测试检查匹配、差异、无效输入和执行失败。外部应用接入测试验证 JSONLogic 可以独立使用。

## 仓库内容

```text
src/                  JSONLogic 运行库与单元测试
src/examples/         可运行的使用示例
compat/               跨实现、跨后端的验证程序
tests/                边界输入 fixtures
tools/                原版执行器、fixture 生成器、兼容性检查
support/casekit/      自主开发的 CaseKit 测试库、CLI 与运行器
third_party/          固定版本的原版 JS、官方测试与许可证
docs/                 API 与兼容性说明
```

修改 fixtures 后执行 `python3 tools/generate_cases.py && moon fmt`。CI 会检查 fixtures、公共 API、各后端单元测试、示例、兼容结果及 CaseKit 失败路径。

## 许可证与来源

两个库均采用 MIT 许可证。

- **JSONLogic**：MoonBit 移植参考 Jeremy Wadhams 的 `json-logic-js`；标准规则格式及原版操作语义归于上游。原版代码和官方测试保留 MIT 许可证；固定提交、文件校验值及来源见 [来源记录](third_party/json-logic-js/README.md)。
- **CaseKit**：由本项目作者 Kaige Liang 自主设计与实现，包含采集、协议、比较、报告、命令行与多后端运行功能。它是本项目的原创库，按 [MIT 许可证](support/casekit/LICENSE) 提供给其他项目复用。
