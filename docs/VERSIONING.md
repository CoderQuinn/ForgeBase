# Versioning and release contract

## English

ForgeBase follows Semantic Versioning and is currently in the `0.y.z`
development phase.

### Compatibility before 1.0

- A patch release (`0.y.z`) contains backward-compatible fixes, documentation,
  tests, or internal improvements. It must not intentionally break a public
  source contract.
- A minor release (`0.y.0`) may change a public source contract. Every breaking
  change must be called out under **Breaking** in `CHANGELOG.md` with a concrete
  migration note.
- Deprecation for at least one minor release is preferred when the old contract
  can remain correct and safe. Unsafe, trapping, lossy, or misleading behavior
  may be replaced immediately and must be documented as breaking.
- Published tags are immutable. Corrections ship as a new version; a published
  version is never silently retagged.

The public compatibility surface includes public Swift and C declarations,
error cases, ownership and `Sendable` requirements, equality and hashing
semantics, invalid-input behavior, and documented byte-order guarantees.

### Dependency policy

Forge packages used by QuantumLink 0.8.0 must pin an exact ForgeBase release.
They must not depend on `main`, a moving branch, or an unreleased revision in a
release candidate. This avoids accepting a future pre-1.0 breaking minor update
without review.

### Release gates

A ForgeBase release requires:

1. An up-to-date changelog and migration notes for every breaking change.
2. Strict formatting, Debug and Release tests, strict concurrency, and the
   production coverage gate passing on the release commit.
3. At least one affected downstream Forge package building and testing against
   the candidate contract.
4. An Admin-authored release PR merged only after fresh green checks.
5. A signed or annotated `vMAJOR.MINOR.PATCH` tag created from the verified
   `main` commit.

## 简体中文

ForgeBase 遵循语义化版本，目前处于 `0.y.z` 开发阶段。

### 1.0 前的兼容性

- 补丁版本（`0.y.z`）只包含向后兼容的修复、文档、测试或内部改进，不得有意破坏公开源码合同。
- 次版本（`0.y.0`）可以调整公开源码合同。每个破坏性变更都必须在 `CHANGELOG.md` 的 **Breaking** 部分明确列出，并给出具体迁移说明。
- 当旧合同仍然正确且安全时，优先至少保留一个次版本的弃用期。对于不安全、会崩溃、信息有损或具有误导性的行为，可以立即替换，但必须标记为破坏性变更。
- 已发布的 tag 不可变。任何修正都必须发布新版本，不能静默移动既有版本。

公开兼容面包括 Swift 和 C 的公开声明、错误类型、所有权与 `Sendable` 要求、相等与哈希语义、非法输入行为，以及文档承诺的字节序约定。

### 依赖策略

QuantumLink 0.8.0 使用的 Forge 子模块必须固定到 ForgeBase 的精确发布版本。发布候选不得依赖 `main`、浮动分支或未发布的 commit revision，避免未经审核就接受未来 1.0 前的破坏性次版本升级。

### 发布门禁

ForgeBase 发布必须满足：

1. Changelog 已更新，并为每个破坏性变更提供迁移说明。
2. 发布 commit 的严格格式检查、Debug/Release 测试、严格并发检查和生产代码覆盖率门禁全部通过。
3. 至少一个受影响的下游 Forge 子模块已针对候选合同完成构建和测试。
4. 发布 PR 由 Admin 发起，并且只在最新检查全绿后合并。
5. 从已验证的 `main` commit 创建带说明或签名的 `vMAJOR.MINOR.PATCH` tag。
