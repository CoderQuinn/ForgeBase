# ForgeBase foundation implementation plan

> Use superpowers:subagent-driven-development. Begin only after coordinator confirms G0 review complete.

**Goal:** deliver this bounded foundation increment with reproducible evidence.
**Architecture:** preserve current production contracts; add verification/tooling and narrowly reproduced fixes.
**Tech Stack:** existing repository toolchain.
**Spec:** [Design](../specs/2026-11-14-foundation-delivery-design.md).

## Global constraints

- Preserve existing public API and original dirty workspaces; work only in the assigned isolated checkout.
- No unrelated dependencies, business routing decisions or host features. Only synthetic fixtures and public repository facts may be committed.
- First-party production and changed executable lines each >=95%; report numerator/denominator and authored C/ObjC/Swift/Go scope explicitly. Do not hide a shortfall with exclusions.
- Unknown/blocked/not_run is not passed. Record exact base..head, toolchain, commands and consumer pins.
- Implementation: GPT-6.1 SOL xhigh. Independent spec and quality review: Astra high. No merge, bypass, tags or release.
- Same-machine performance runs are serialized by the coordinator; building/testing may run concurrently, timing claims must wait for exclusive access.

## Review Focus

- Evidence generated from a different revision or dirty input being presented as qualified.
- Error handling that changes existing outputs or leaks borrowed memory/secrets.
- Duplicate tests that miss actual API/adaptor boundaries.
- Coverage exclusions concealing authored code and inherited changes being credited as new.
- Missing build/reader/performance capability being labeled passed.

### Task 1: Reproducible borrowed-buffer benchmark and consumer proof

**Files:** `Benchmarks/UDPIPPacketBuilder/main.swift`, `Scripts/benchmark-udp-builder.sh`, new focused benchmark/consumer test helpers if necessary, README and this spec. Production builder/buffer default unchanged.
**Interfaces:** existing `FBPacketBuffer.withUnsafeReadableBytes` and `FBUDPIPPacketBuilder.buildUDPIPv4(...payloadBuffer:...)`; additive benchmark CLI/result JSON only.

- [ ] Freeze exact CLI/result schema in spec. Run baseline contract tests and inspect current CI/coverage commands.
- [ ] RED: malformed provenance/missing history and oracle mismatch must reject; borrowed window/fallback must validate against independent bytes.
- [ ] Implement the smallest benchmark/result/consumer harness additions. Preserve validation precedence and lifetime semantics.
- [ ] GREEN: Debug/Release, strict concurrency warnings-as-errors, existing format/coverage gate, focused harness tests, clean consumer exact lock. Audit first-party C coverage and changed executable lines as well as Swift. Record not_run rather than inventing benchmark data.
- [ ] Commit scoped changes and full report; request coordinator's exclusive benchmark slot for a native Release smoke run. Keep native timing separate from coverage/sanitizers.
