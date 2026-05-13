# FAGAN Pattern Library

> 17 patterned-finding shapes distilled from the cycle-032 substrate-runtime session (PR loa-finn#157, merged 2026-05-04, b895f888) where Opus 4.7 reviewed twice (16 findings each, score plateau 23 → 23, no convergence) and GPT-5.5 via codex CLI reviewed once and surfaced 3 contract-violating issues neither Opus pass had found.
>
> P18 added 2026-05-13 from a separate lineage — THJ identity-spine doctrine + `0xHoneyJar/score-mibera#109` boundary violation. Architectural pattern, not from cycle-032; generalizable to any architecture with a named identity layer.

This file is FAGAN's pattern checklist. Reference it during review. Each pattern: surface signal · mechanism · named CVE family · one example. Severity defaults are FAGAN-binary (critical or major). Style/quality patterns are excluded — FAGAN doesn't review those.

---

## P1 · Capability check at load-time, not execution-time

**Surface signal**: search for a `validates X` step at one layer and `always provides X` at the layer below.

**Mechanism**: An authorization or capability check runs at LOAD time (parent loader, IAM evaluation), but the EXECUTION layer doesn't enforce. The check becomes a façade — present in the audit trail, absent on the actual control path.

**Severity**: critical (security)

**Named family**: CWE-285 missing authorization · BOLA · AWS S3 bucket-policy-vs-IAM split-brain.

**Example**: cycle-032 C1 — `worker-runtime.ts:createRuntimeForSlug` always merged both `modelRunnerLayer` + `eventWriterLayer` regardless of `manifest.requirements`. Capability bound enforced at parent loader, ignored at runtime composition.

---

## P2 · Identity must propagate per-invocation, not per-component

**Surface signal**: hardcoded `""` in metadata fields adjacent to dynamic `trace_id` or per-call values.

**Mechanism**: Runtime context (tenant_id, agent_id) is HARDCODED in a component built at boot, even though per-call options carry the values. Refactors that move identity propagation responsibility leave empty placeholders behind.

**Severity**: critical (multi-tenant isolation)

**Named family**: CWE-639 authorization bypass through user-controlled key. Atlassian 2018-class regressions.

**Example**: cycle-032 C2 — `metadata: { agent: "", tenant_id: "", nft_id: "", trace_id: subJobId }`. Three hardcoded empties next to one dynamic value. `runtimeOpts` carried `tenantId` to the worker but never reached `completionRequest`.

---

## P3 · Every async wait needs a timeout

**Surface signal**: `pendingX.set + postMessage/fetch` with no setTimeout. `new Promise((resolve, reject) => { register; send })` shape.

**Mechanism**: IPC/network/IO await with no bound. Missing response (parent crash, queue overflow, network blip) wedges the awaiter forever.

**Severity**: major (resource leak under fault conditions)

**Compounding hazard**: When combined with "defer dispose until in-flight is 0" patterns, unbounded wait → permanent leak.

**Named family**: CWE-833 deadlock. Connection-pool-during-shutdown (AWS Lambda extensions postmortem).

**Example**: cycle-032 C3 — `pendingBridgeRequests.set(...)` followed by `port.postMessage()` with no timer. Combined with F17's defer-dispose, missed response → permanent runtime leak.

---

## P4 · Verify and act on the SAME bytes the crypto check validated

**Surface signal**: `await someVerify(token, key)` followed by `token.split(...)` and a manual base64-decode.

**Mechanism**: Signature verification succeeds on input A, code manually re-parses A → A' and acts on A'. Any divergence between the two parsers is a parse-differential surface.

**Severity**: critical (auth bypass class)

**Named family**: SAML XML signature wrapping (CVE-2008-3437 + descendants), JWT alg confusion (auth0 jsonwebtoken CVEs 2015-2022). OWASP JWT cheat sheet "verify-then-use" rule.

**Example**: cycle-032 F10 — `compactVerify(token, publicKey)` succeeded, then code did `token.split(".")` + manual base64url decode. Fix: use compactVerify's returned `{ payload }` bytes.

---

## P5 · Test infra that swallows errors becomes invisible debt

**Surface signal**: `try { compile() } catch { fileExists() }` patterns. `--noEmitOnError false` flags. `|| true` in shell pre-checks.

**Mechanism**: Defensive `try/catch` in test setup or build infra continues on failed precondition. Real failures get hidden behind a "this passes vacuously" path.

**Severity**: major (broken bug-detection layer)

**Named family**: CI/CD black-hole-of-warnings antipattern. Linus Torvalds "do not silently swallow errors" doctrine.

**Example**: cycle-032 F5 — e2e test's `beforeAll` ran tsc with `--noEmitOnError false`, caught failure, then verified worker-entry.js exists. Real type errors in substrate code would silently emit broken JS; e2e ran against it.

---

## P6 · AsyncLocalStorage propagates through Promise chains, NOT through cached components

**Surface signal**: `als.run(value, async () => longLivedComponent.use())` where `longLivedComponent` was cached from a prior call.

**Mechanism**: ALS context-as-frame works only when the read happens INSIDE the active frame's Promise chain. A component cached across invocations that reads getStore() at construction-time (instead of at call-time) reads the FIRST invocation's snapshot — or null.

**Severity**: critical (incorrect-context-leak)

**Named family**: Datadog dd-trace 2021 (request-scoped context leaking between HTTP requests). OpenTelemetry's explicit `Context.with()` design choice.

**Example**: cycle-032 F1 — bridge proxy Layers cached in `runtimeCache` per slug, but proxy reads `invocationContext.getStore()` AT proxy-call time inside `Effect.tryPromise` — verified correct via regression test.

---

## P7 · Discriminated-union narrowing requires `--strict`

**Surface signal**: tsc invocations with explicit flag lists that don't include `--strict`. Test `beforeAll` hooks that compile sources standalone.

**Mechanism**: TypeScript narrowing semantics differ between strict and loose mode. `if (!parsed.ok)` narrows `ParsedArgs | ParseError` under `--strict` but produces TS2339 "property doesn't exist on union" under loose.

**Severity**: major (false-positive type errors block build, OR mask real type errors)

**Example**: cycle-032 F5 follow-up — e2e standalone tsc didn't include `--strict`. Adding the precondition surfaced 4 false-positive narrowing errors that were valid under the project's `--strict`. Fix: align test infra strictness with project tsconfig.

---

## P8 · Path-prefix matching needs trailing-separator guard

**Surface signal**: `Set<string>` of trusted prefixes + `for (const p of set) if (modPath.startsWith(p)) return true`.

**Mechanism**: `path.startsWith(prefix)` where prefix is `/foo` matches `/foo/bar` (correct) AND `/foo-evil/bar` (collision attack).

**Severity**: critical (path traversal class)

**Named family**: CVE-2019-14271 docker cp et al. CWE-22 path traversal.

**Example**: cycle-032 F4 — `registerTrustedPacksDir` correctly appended `sep` to make prefix `/trusted/packs/`. Test coverage for the explicit collision case was missing.

---

## P9 · Cross-model dissent is the gate, not depth-of-iteration

**Surface signal**: severity-weighted score equal across consecutive single-model iterations; finding IDs change but counts don't.

**Mechanism**: A single model reviewing the same code N times finds DIFFERENT compositions of issues at the SAME severity-budget level. The illusion of progress masks lack of convergence.

**Severity**: meta (this is FAGAN's reason for existing — the gate other reviewers can't be)

**Example**: cycle-032 BB iter-1 vs iter-2 — score 23 → 23 across two Opus passes. Adding 1 GPT-5.5 pass found 3 NEW contract-violating issues neither pass had surfaced.

**Doctrine**: For security/contract code, cross-model review is mandatory. For style/quality code, single-model multi-pass is acceptable.

---

## P10 · "Defer X until safe" needs explicit drain semantics

**Surface signal**: code that does "queue dispose until count==0" without a timeout backstop on what increments the counter.

**Mechanism**: The defer pattern is half the answer. The OTHER half is the trigger for the drain — and what happens if the trigger never fires.

**Severity**: major (composes with P3 to form permanent leaks)

**Example**: cycle-032 F17 + C3 interaction — F17 added defer-dispose. C3 found that without bridge-proxy timeouts, the in-flight counter never decremented, deferred dispose never drained.

**Doctrine**: When you ship "defer until safe", ALSO ship the timeout that bounds the wait. Treat as a pair.

---

## P11 · Fix-as-review-surface paradox

**Surface signal**: review iter-N+1 finds issues in code added by iter-N's fixes.

**Mechanism**: Every fix shipped becomes review surface. New tests, new comments, new patterns can themselves attract findings on the next pass.

**Severity**: meta (operator-stop guidance, not a code finding per se)

**Doctrine**: For single-model loops, operator-stop is the right termination signal. Score-plateau (kaironic stop) works in theory but in practice the same model finds new SHAPES at the same DEPTH. Cross-model is the answer.

---

## P12 · Hardcoded test fixtures become hardcoded prod values during refactors

**Surface signal**: code that has both a parameter (e.g., `runtimeOpts.tenantId`) AND a downstream usage hardcoded to empty.

**Mechanism**: Test fixtures use `""`, `"test-tenant"`, `0xdeadbeef`. Refactors that move values around lose tagging that says "this MUST be replaced before prod." Empty strings ship.

**Severity**: critical when in security/identity context, major otherwise

**Example**: cycle-032 C2 root cause — `tenant_id: ""` in metadata while `runtimeOpts.tenantId` carried the real value into the worker.

**Doctrine**: Tag test sentinels with `as const TEST_FIXTURE` brands. Never hardcode `""` in metadata fields; thread from real source or fail loud.

---

## P13 · Atomic operations are atomic ONLY when bookkeeping fits in atomic-rename

**Surface signal**: scripts/migrations described as "atomic" with phases AFTER the actual atomic step.

**Mechanism**: Multi-step "atomic" sequences (file swap + checksum bookkeeping + version-marker update) are atomic only for steps that fit within one rename or transaction commit. Failures after the rename leave partial state.

**Severity**: major (recovery path required)

**Example**: framework update v1.99.2 — Fetch → Validate → Migrate → Swap was labeled "atomic." The Swap (rename) was atomic, but the "Generate cryptographic checksums" phase after the swap hung on coprocess pipe under disk-full. Recovery via partial-state acknowledgment.

**Doctrine**: Treat the whole sequence as the operation. Document partial-state recovery. Add an idempotent "finalize" step.

---

## P14 · Single-writer semantics need explicit documentation

**Surface signal**: code that does "delete + set" or "read-modify-write" without locking, in a context where concurrent execution would be a bug.

**Mechanism**: Code safe under runtime assumption (e.g., "worker_threads = single-thread JS") becomes unsafe when lifted to multi-thread or distributed. Refactors don't always update the safety analysis.

**Severity**: major (latent race when assumption changes)

**Example**: cycle-032 worker-runtime.ts:284-292 — LRU eviction does delete + set. Comment: "worker_threads are single-threaded JS — no concurrent calls can interleave. If lifted to multi-thread/process pool, the delete+set sequence MUST be guarded by an async mutex."

**Doctrine**: Code correct only under a runtime assumption MUST document the assumption AND what would invalidate it.

---

## P15 · Dispatch-guard hooks at platform layer, not skill layer

**Surface signal**: rules in skill markdown that say "MUST NOT do X" with no PreToolUse hook backing them.

**Mechanism**: Instructions in CLAUDE.md / SKILL.md are advisory — agent reads and SHOULD follow. PreToolUse hooks fire at platform layer before tools execute — they ARE enforcement.

**Severity**: architectural (design-review territory, not code-review)

**Example**: loa /spiraling skill — SKILL.md says "MUST dispatch through harness pipeline" but ALSO ships `spiral-skill-sentinel.sh` (auto-creates dispatch sentinel) and `spiral-dispatch-guard.sh` (blocks code edits until harness runs). The hooks ARE enforcement; the SKILL.md is advisory.

**Doctrine**: For invariants that MUST hold, wire as platform hooks. Document advisory vs mechanical so reviewers know which layer the bug-class lives at.

---

## P16 · Findings reference IDs and finding-source for traceability

**Surface signal**: commit messages on a fix-iteration branch without finding IDs. `fix: address review feedback`.

**Mechanism**: Generic commit messages become unmoored from their justifying review iteration. Future readers can't walk back to the review.

**Severity**: process-class (not a code finding per se, but a PR-quality flag)

**Doctrine**: For any iterative review/fix cycle, commit messages MUST reference finding ID + reviewer source: `fix(F1, BB-iter1): ALS test for cached runtime`, `fix(C2, codex-gpt5.5): thread runtimeOpts via ALS`.

---

## P17 · The seven-layer test gap

**Surface signal**: security-touching code shipped without layer-6 (multi-model) review. Tests at layers 1-3 only.

**Mechanism**: Test layers catch different bug shapes:
1. unit · 2. integration · 3. e2e · 4. manual exploratory · 5. peer review · 6. multi-model adversarial · 7. production canary.

Most projects ship at layer 3-5. Layer 6 is what FAGAN/this construct addresses.

**Severity**: process-class (PR-quality flag for security-touching code)

**Doctrine**: For security-touching, contract-defining, or isolation-layer code, layer 6 is mandatory. For business logic, layer 5 is sufficient. The differentiator is "what's the cost of shipping a missed contract violation."

---

## P18 · Cross-system identity emission (two-writers class)

**Surface signal**: a new tool / endpoint / response shape on a non-identity system (analytics, scoring, content, leaderboard, indexer) emits identity fields alongside the wallet / canonical-key it actually operates on.
- Generic identity fields: `handle`, `display_name`, `user_id`, `pfp_url`.
- Domain-specific variants a reviewer in that domain will recognize: `discord_id`, `discord_username`, `mibera_id`, `ENS_name`, etc. (THJ-specific examples; substitute the equivalent for the host architecture).

**Mechanism**: Architectures with a named identity layer (`freeside-as-identity-spine`-class designs · OAuth-style canonical-user-id systems · SSO with canonical ID · multi-tenant SaaS with profile service) explicitly assign **one** system as the wallet→handle / credential→user_id resolver. Other systems read wallets / canonical IDs only. When a non-identity system starts emitting identity fields **without an explicit staleness contract or refresh mechanism**, it becomes a second writer to identity — its responses become a stale cache, its deploys gate on profile schema changes, wallet-linking events ripple through it, and authentication-state drift between the two writers becomes a recurring bug class.

**Note on the "two writers" framing**: the title names the most common form — a system that originates identity values independent of the spine. The same violation surfaces when a system *reads* identity from the spine, *caches* it, and *re-emits* it in its own response shape without a staleness contract. No second write occurred, but the emission shape still couples downstream readers to a stale snapshot. The check is on the emission shape + missing contract, not on the write operation alone.

**Severity**: major (architecture / data integrity / cross-app session contamination class)

**Named family**: two-writers antipattern · service-mesh authorization sprawl · provider-keyed-JWT bug class (canonical mechanism: shared cookie domain + separate per-brand profile tables + provider-internal `sub` claim → cross-app session contamination when a wallet is relinked; observed in production 2026-02-17 on THJ stack).

**Example**: `0xHoneyJar/score-mibera#109` (2026-05-13) proposed a `resolve_identities` tool on score-mibera returning batch `wallet → display_name / discord_id / mibera_id`. THJ's operator-confirmed boundary doctrine (2026-04-29) explicitly rejected this shape: *"score-mcp ships factor metadata (UNIX self-description). identity (wallet → handle) lives in freeside. they cross paths but never conflate."* Drift class: wallet-linking event on the identity layer → stale identity cached in score response → downstream consumer (Discord bot, dashboard) shows wrong handle on next read.

**Doctrine**: The identity-emitting system is NAMED explicitly in the architecture. Non-identity systems read wallets / canonical IDs only. Reviewer-side check: when a diff adds a new tool / endpoint / schema field on a non-identity system, search the response shape for identity-typed fields. If found:
- cite the architecture's identity-spine doctrine
- ask whether the use case can route through the identity layer instead
- if batch / performance is the justification, the answer is "build batch on the identity layer," not "duplicate the identity layer"

**Carve-out for read-model projections** (avoid false-positives on legitimate CQRS / materialized-view patterns):

The violation shape is *"emission without a staleness contract that covers the actual violation surface,"* not *"any system that returns identity fields."* Before filing a finding, verify whether the system is:
- a **secondary writer / emitter without contract** (no staleness contract, no refresh mechanism, schema drift expected) → genuine P18 violation
- a **read-optimized projection** (CQRS read model, materialized view, API gateway aggregation layer with explicit refresh triggers and a schema versioned against the identity layer) → legitimate pattern, not a violation

But contract presence is *necessary, not sufficient*. The contract must cover the actual violation surface — the event class that drives the canonical bug. A TTL-only refresh contract passes the "contract exists" check but still drifts on wallet-relinking (the SatanElRudo class) unless wallet-relink is named as an explicit invalidation trigger. When a contract is present but the load-bearing event class isn't covered, the projection still drifts on the failure mode P18 names. Check for: (1) named refresh triggers, (2) bounded lag window, (3) invalidation on the specific events that mutate identity (wallet relink, credential reassignment, profile merge).

The pattern generalizes beyond THJ: any architecture with a profile service / canonical user table / SSO identity provider has the same temptation when a downstream system "needs" enriched identity data for its own response shape. When no explicit staleness contract is defined, the fix is to push the enrichment to the identity layer, not to duplicate it.

---

## P19 · Duplicate emission at layer seam (the test-bypass-trap)

**Surface signal**: code change has TWO adjacent layers BOTH emitting/mutating the same conceptual signal (event, resource, state field, log entry). Each layer's tests cover its own emission · neither test exercises the production wiring that combines both. The composed path fires the signal twice.

**Mechanism**: classic duplication-at-seam:

```typescript
// Layer A (e.g., command-queue.ts)
function enqueue(cmd) {
  // ... validate ...
  bus.emit({ type: "CardCommitted", ... });  // ← Layer A emits
  queue.push(cmd);
}

// Layer B (e.g., resolver.ts · pure function · returns events array)
function resolve(state, cmd) {
  return {
    nextState: ...,
    semanticEvents: [
      { type: "CardCommitted", ... },  // ← Layer B emits in returned array
      // ... other downstream events
    ],
  };
}

// Production composition (e.g., BattleV2.tsx) wires BOTH layers
const r = queue.enqueue(cmd);      // ← Layer A's emit fires on bus
const drained = queue.drain();
const result = resolve(state, drained[0]);
for (const event of result.semanticEvents) {
  bus.emit(event);                 // ← Layer B's CardCommitted ALSO fires
}
// → CardCommitted on bus TWICE → downstream consumer (sequencer, telemetry,
//   state machine) fires twice → 2× the work / 2× the side-effects
```

**Why tests miss it**: replay/unit tests typically call ONE layer in isolation. Layer-A test sees Layer-A's emission · Layer-B test (resolver replay) sees Layer-B's emission in the returned array. Neither test exercises the production composition that wires BOTH onto the bus.

**Real instance**: compass-cycle-1 wood-vertical-slice (2026-05-13). `command-queue.ts` emits `CardCommitted` on accepted PlayCard enqueue. `resolver.ts` ALSO emits `CardCommitted` in its `semanticEvents[]` output (intentional · so resolver-only callers see the full event sequence for AC-7 golden replay). Production `BattleV2.tsx:handleZoneClick` does `queue.enqueue(...)` + iterates resolver's `semanticEvents` and bus.emits each → CardCommitted twice → wood_activation_sequence schedules 22 beats instead of 11. 108 vitest assertions all green · bug only visible in browser interaction. Caught by manual self-review (BB-equivalent · because BB-via-cheval choked on PR diff size).

**Severity**: critical (correctness · downstream side-effects double · presentation timing breaks · audit trail falsified)

**Related weakness shape**: double emission across a shared event boundary, comparable to TOCTOU-style race conditions in that the bug appears only when two independently valid layers are composed.

**Reviewer heuristic**: when a diff adds OR modifies a layer-spanning event/state-mutation, walk:
1. Identify EVERY layer that emits the signal (grep the type/field across the codebase)
2. Identify the production COMPOSITION (the React component · the orchestrator · the entry point that wires layers together)
3. Trace which emissions actually reach the bus / shared state under composition
4. If multiple layers emit, identify which layer's emission is canonical · which layer's must be suppressed at composition time
5. Verify a test exercises the COMPOSED path (not just isolated layer tests)

**Fix shape** (one of):
- (a) Suppress at composition time: skip the redundant emission in the composer (`for (const event of r.semanticEvents) { if (event.type === "CardCommitted") continue; bus.emit(event); }`)
- (b) Choose canonical layer: remove emission from the non-canonical layer entirely
- (c) Dedupe at consumer: subscriber tracks seen events within a small time window (only when (a) and (b) are infeasible · introduces fragility)

**Doctrine**: when reviewing code that has multiple layers BOTH emitting/mutating the same conceptual signal, **the test surface that catches single-layer correctness does NOT catch composed-layer correctness**. The reviewer must trace the production composition, not trust isolated layer tests.

**Composition note**: pairs with P15 (dispatch-guard hooks at platform layer · same family of "test-bypass-trap" where production wiring is the bug surface)

---

## How FAGAN uses these patterns

When reviewing a diff:

1. **Walk each pattern P1-P19 against the changed lines.** Does the code exhibit the surface signal?
2. **For each match, generate a finding** with file:line, current_code, fixed_code, explanation.
3. **Severity is binary**: critical (security/auth/parse-differential/multi-tenant) or major (correctness/lifecycle/concurrency). Style/quality patterns excluded — that's craft-gate (artisan) territory.
4. **Tag the named CVE family** when applicable. Anchors abstract concerns to concrete prior incidents.
5. **For meta-class patterns (P9, P11, P15, P16, P17)**: surface as design-review concerns at the SUMMARY level, not as line-anchored findings.

## Composition: which patterns matter most for which review type

| review type | patterns to prioritize |
|---|---|
| security/auth diff | P1, P2, P4, P8, P12 |
| concurrent/async refactor | P3, P6, P10, P14, P19 |
| isolation/sandbox boundary | P1, P2, P3, P14, P15 |
| crypto/JWT/signing | P4, P12 |
| test infrastructure changes | P5, P7 |
| migration/atomic ops | P13 |
| event-driven / pub-sub / state-mutation refactor | **P19**, P3, P14 |
| layered architecture (resolver+queue, port+live, etc.) | **P19**, P11, P15 |
| process meta-review | P9, P11, P16, P17 |
| identity / multi-system architecture | P18 |
| new MCP tool / API endpoint shape | P1, P2, P18 |
