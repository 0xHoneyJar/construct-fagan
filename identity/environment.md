# The Ground FAGAN Stands On

> Shared ground: https://github.com/0xHoneyJar/loa-constructs/blob/main/docs/the-ground.md
> — this file carries ONLY the fagan-specific layer. Tiers, forks, agent
> types, frontmatter contracts, and gate design live THERE, not here.
> Probed from the live harness at construct-fagan @ 1970e6e, 2026-07-03.

## 1. Runtime contract (probed)

| Axis | Value | Source |
|---|---|---|
| schema_version | 3 | construct.yaml:1 |
| model_tier | **not declared** — no `capabilities` block anywhere in the manifest | construct.yaml (absent) |
| danger_level | not declared | construct.yaml (absent) |
| effort_hint | not declared | construct.yaml (absent) |
| downgrade_allowed | not declared | construct.yaml (absent) |
| execution_hint | not declared | construct.yaml (absent) |
| requires | tool_calling / vision — not declared | construct.yaml (absent) |
| workflow.gates | **none** — fagan owns no pipeline stage; it reviews AFTER an implementer | construct.yaml (absent) |
| agent dispatch | neither skill sets `agent:` — both inherit the caller (the safe default) | skills/*/SKILL.md frontmatter |
| reviewing-diffs tools | Bash, Read (read-only) | skills/reviewing-diffs/SKILL.md:4 |
| reviewing-files tools | Bash, Read (read-only) | skills/reviewing-files/SKILL.md:4 |
| external toolchain | codex CLI · jq · bash >= 4 | construct.yaml:63,64,65 |
| required env | OPENAI_API_KEY | construct.yaml:67 |

The review does its real work in a subprocess: the codex CLI (gpt-5.5 backend
by default, overridable via `CODEX_REVIEW_MODEL`, construct.yaml:63) is invoked
through Bash, and findings come back as JSON on stdout. No Claude write tool is
in either skill's `allowed-tools` — the deck is read-only by construction.

## 2. Capability-reality edges

- **#553 class: N/A — structurally impossible here.** Both skills declare
  `allowed-tools: [Bash, Read]` (skills/reviewing-diffs/SKILL.md:4,
  skills/reviewing-files/SKILL.md:4) and neither sets `agent:`. The
  silent-output-drop conflict needs a write tool to drop; fagan carries none,
  so the edge cannot exist. Clean, by design, not by luck — a code reviewer
  that cannot mutate the code it reviews is the correct shape.
- **No `capabilities:` block anywhere (SMELL, surfaced).** The manifest
  declares no `model_tier`, `danger_level`, `downgrade_allowed`, or
  `requires.*` (construct.yaml — absent throughout). Under the shared ground's
  deny-all default, an undeclared tier means the runtime routes fagan on its
  own default rather than an intended one. For a construct whose single job is
  one adversarial GPT pass, the intended tier is a real routing decision the
  manifest currently leaves unstated. This is a SMELL, not a CONFLICT: nothing
  contradicts, one layer is simply silent. The operator decides whether to pin.
- **Gate ownership: none, correctly.** `workflow.gates` is absent
  (construct.yaml) and `events.consumes` is `implement.diff.created`
  (construct.yaml:48). fagan is composed AFTER the implementer it reviews
  (`compose_with:` general-purpose / artisan / flatline, construct.yaml:37-40),
  never a stage that owns a gate itself. The contract matches the identity: the
  inspector arrives after the work, holds no key of its own.

## 3. What FAGAN does with the ground

fagan is the formal inspector — Michael Fagan, IBM 1976 — who reads the diff
and refuses to be charmed by it. the ground it needs is deliberately narrow:
read the code, shell out to one hard GPT pass, hand back line-anchored findings
in a fixed JSON shape, and converge. it asks for no pen, because a reviewer that
can edit the code has already compromised the review. no gate of its own,
because the inspection rides the caller's pipeline, not fagan's. the one thing
its ground leaves unspoken is its own tier — the manifest never names how heavy
a mind the single pass deserves, and that silence is the one edge worth the
operator's eye.
