# JSONLogic 存量筛选规则接入 QueryX/foxql

仓库源码提供 `kaigeliang/jsonlogic/queryx` **native** 接入包。它将有类型约束的 JSONLogic 筛选规则导入现有 QueryX 表达式，复用 foxql 生成参数化 SQL。已发布的 Mooncakes 0.1.0 只包含求值核心；适配器当前通过源码 workspace 使用。

## 要解决的问题

面向保存了 JSONLogic 筛选规则、需要在 MoonBit 后端继续复用配置查询数据的应用。[React Query Builder 的导出文档](https://react-querybuilder.js.org/docs/utils/export#jsonlogic)提供这种规则格式的实际来源；它也能导出 SQL 等格式。本项目的目标输入限定为存量 JSONLogic 配置。验证使用实际查询构建器导出的 fixtures；目前没有生产应用接入报告。

## 与现有生态的关系

[QueryX](https://github.com/jaredzhou/moonbase/blob/main/queryx/README.mbt.md) 已支持自己的 JSON 筛选 DSL、`Expr` 求值、`FieldResolver` 和 foxql 桥接，其文档示例输入为 `{"filter":{"age":{"gt":18}}}`。标准 JSONLogic 则使用 `{">":[{"var":"age"},18]}` 这样的操作对象。

接入模块的职责是将受约束的 JSONLogic 筛选规则导入既有 QueryX `Expr`，复用 QueryX/foxql 的字段解析、SQL 生成与查询构建。导入过程判断规则是否在可保持语义的范围内，并解释拒绝原因。

JSONLogic 求值库是基础组件和结果对照工具。求值核心保持四后端支持；QueryX/foxql 及本适配包仅支持 native。查询验证单独比较原版 JS、MoonBit 求值、QueryX 本地求值和真实 PostgreSQL 结果。

## 输入与输出

输入：

- 原始 JSONLogic 筛选规则。
- 由服务端提供的字段白名单、字段类型、非空约束和数据库字段映射。
- 类型相同的常量。`Number` 固定为 Int32 整数，范围为 -2147483648 到 2147483647；字符串为有效 Unicode 且无 NUL；布尔值必须是 JSON true / false。

支持：

- 静态顶层 `var` 字段与同类型常量比较，支持字段放在任一侧。`var` 可使用字符串或单元素字符串数组，不接受默认值。
- Int32 的 `==`、`===`、`!=`、`!==`、`>`、`>=`、`<`、`<=`；字符串和布尔值仅接受相等／不等。
- `and`、`or` 的非空组合与单参数 `!`；每个叶节点必须是比较。独立布尔常量和裸 `var` 拒绝。
- `validate_record` 校验记录的所有声明字段；额外字段允许，但仍检查完整 JSON 的深度、节点、数值和 Unicode。

输出：

- 成功：既有 QueryX `Expr`，以及支持范围与字段映射记录。
- 拒绝：规则 JSON Pointer、原因和涉及字段；不删除或改写原始规则。

最终由现有 foxql 桥生成参数化 SQL。适配器不得拼接调用方提供的 SQL 片段。

应用必须先校验 JSON 记录，并使用与声明一致的 PostgreSQL `INTEGER`／`TEXT`／`BOOLEAN NOT NULL` 列。文本列指定 `COLLATE "C"`，字段映射由可信 `FieldResolver` 提供。验证程序将声明字段映射到固定 SQL 列 `f0`、`f1` 等。

直接使用 QueryX Expr，不经过 `to_json` 后重新解析。配套 QueryX 的序列化会合并部分相同字段的区间条件，可能改变严格边界；本接入路径保持原始表达式树。

## 必须明确处理的语义差异

| 问题 | 当前处理 |
| --- | --- |
| 缺失字段、显式 null、SQL NULL | 记录校验要求声明字段存在且非空，数据库需相同非空约束 |
| JSONLogic 隐式类型转换 | 同类型约束无法满足时拒绝 |
| 数值精度、整数范围与数据库类型 | 仅接纳 Int32 整数，避免桥接的 Int64 → Int 窄化；小数和越界整数拒绝 |
| 字符串排序、相等性与数据库 collation | 字符串仅同型相等／不等，PostgreSQL 文本列用 `C` collation；排序比较拒绝 |
| `and` / `or` 返回非布尔操作数 | 仅接纳可证明各子项返回布尔值的筛选组合 |
| 空布尔组合与无效参数数量 | 拒绝，不直接透传给 QueryX/foxql |
| 动态变量、默认值、集合与计算操作 | 拒绝 |
| 自定义 JSONLogic 操作 | 拒绝；RQB 的 startsWith / endsWith 等扩展不自动视为标准操作 |

基础求值库与数据库适配器的支持范围不同。导入和记录校验默认各限制 10000 个 JSON 节点、64 层深度；深度配置范围 1–128，字段声明数量 1–1000。错误包含种类、JSON Pointer 与原因。

## 三个接入验证场景

1. **用户人群筛选**：存量 JSONLogic 中的年龄与状态条件导入 QueryX，再经 foxql 查询数据。相同数据集上比较 JSONLogic、QueryX 本地求值、数据库的匹配用户 ID。
2. **订单记录查询**：状态与金额条件使用服务端字段映射；包含边界值与字段名不一致的记录，比较三条路径的匹配订单 ID。
3. **语义拒绝与修订**：导入含类型转换、动态变量或集合规则的配置，输出具体位置与原因；用户修订为支持子集后，重新完成同样的一致性验证。

这些场景由 `tests/queryx_fixture.json`、`src/examples/queryx/` 与 `tools/check_queryx.py` 实际验证；基础求值示例另行保留。

## 复现验证

需要可连接的 PostgreSQL、`psql`、Node.js、Python 和 MoonBit。连接使用标准 PG 环境变量，默认数据库为 `postgres`。运行：

```sh
moon update
npm ci --prefix tools/queryx-fixtures
node tools/queryx-fixtures/generate.mjs --check
python3 tools/check_queryx.py
moon test src/queryx --target native --deny-warn
python3 tools/check_consumer.py
```

验证器只使用临时表、类型化 `PREPARE` / `EXECUTE` 和事务回滚。输出保存在 `output/queryx/<run>/`，其中 `report.json` 记录规则来源、固定版本、匹配 ID、SQL、参数、拒绝诊断和负控；原始命令、stdout/stderr 与 SQL 文件一起保存。

当前结果：

- RQB core 8.24.3 的 9 个未修改导出规则，96 次记录求值；JS 2.0.5、MoonBit core、QueryX、PostgreSQL 17.10 的匹配 ID 全部一致。
- 18 个规则拒绝与 8 个记录拒绝用例；种类和 JSON Pointer 与独立 fixture 预期一致，原因与可读消息非空。
- 故意修改 SQL 参数后检测到匹配 ID 差异，验证失败检查有效。
- 16 个 native 适配器单元测试；独立应用可导入公共适配包。

QueryX 0.2.1、foxql 0.1.3 固定使用配套版本。根模块增加 x 0.5.5 以兼容当前工具链的正则语法；下载的上游源码未修改。结果适用于上述子集、版本及数据，不能扩展为全部 JSONLogic 或任意数据库 schema 的等价性保证。

## 后续扩展

- 根据数据库类型约定扩展数值范围、小数或 nullable 字段，每项补充跨实现对照。
- 根据实际存量配置增加可验证的操作；保留无法保持语义时的明确拒绝。
- 收集实际下游应用接入案例；发布包含适配器的新 Mooncakes 版本。
