# Grok Harness Efficiency Audit

```yaml
status: DIAGNOSTIC_ONLY
gate_effect: none
no_gate_effect: true
codex_verification_pending: true
author_surface: grok
scope: idol_song_mv_harness_static_efficiency
mutations_applied: false
report_authority: diagnostic_only
```

## 1. Audit status

- `DIAGNOSTIC_ONLY`
- `NO_EXISTING_FILES_MODIFIED`
- `CODEX_VERIFICATION_PENDING`
- Branch: `main`
- Commit: `3ce8927fe652c7429edfd165ec8b0b1cc6ec21b1`
- Investigation start (UTC): `2026-08-02T12:19:06Z`
- Investigation end (UTC): `2026-08-02T12:24:31Z`
- Repository root: `/Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL`
- Report path existed before audit: **NO**
- Start worktree fingerprint:
  - `git status --porcelain` line count: `1522`
  - SHA-256 of porcelain snapshot: `e5045e3aa1a25a9bc81402e603f44a5b2e67127ec86ab2ee6e62367cf05779c7`

### Investigation scope

In scope:

- Active IDOL song/MV harness registries, validators, scripts, and operator docs:
  - `AGENTS.md`, `policies/harness-routing-and-sources.md`, `wiki/harness-maintenance-rules.md`, `wiki/production-system.md`, `scripts/README.md`
  - `automation/harness-stage-registry.yaml`, `automation/harness-contract-version-registry.yaml`, `automation/harness-surface-version-registry.yaml`, `automation/instruction-surface-policy.yaml`
  - Active `scripts/**` validation call graph centered on `validate_json_schema.py`, `idol_harness_state_check.rb`, registry validators, and skill/script registry checks

Out of scope (not expanded):

- `cf/**`, `web/**`, `business-marketing/**`, `.git/**`, `.runtime/**`, virtualenvs, `node_modules`
- Media bytes, past run creative outputs, archive/legacy materials as production precedent
- Production skill execution, stage authoring, image/video generation, paid/external work
- Subagents, network, external MCP, full test suites, full production flows

Cross-scope observation only if an active top-level script directly calls excluded paths: none expanded; CF mentions in README/state_check text remain out of scope.

## 2. Executive summary

This audit is a static, non-mutating efficiency diagnosis of the active IDOL song/MV harness validation layer. The harness already separates schema shape checks, semantic registry rules, run-artifact readiness, and Founder/creative gates; that layering is largely intentional and must not be collapsed into a single pass. The dominant efficiency pattern is not “too many creative gates,” but **broad repo-maintenance validation being nested inside every run-state check**, plus a few pure double-validations of the same unchanging bytes inside one process tree. Four official read-only baseline commands were run: three failed on existing integrity/registry drift, one passed with size warnings only. Those baseline failures are integrity debt, not efficiency debt. Among efficiency findings, the highest-confidence candidates are (1) double JSON-Schema validation of the surface-version registry inside `idol_harness_state_check.rb`, (2) unconditional full-repo surface/script/skill scans on every run state check, and (3) duplicated skill path-contract logic across two always-on checkers. Required repetitions that should be preserved include pre/post-write validation, producer vs consumer checks, schema-then-semantic layers with different rules, and frontier vs full-audit separation. No timing benchmarks were collected; cost statements are **qualitative only**. No harness file was modified; only this diagnostic report was written. This report grants no stage entry, PASS, approval, or repair authority.

| Bucket | Count |
|---|---:|
| Confirmed efficiency candidates (`CONSOLIDATE` / `CACHE` / `SCOPE_REDUCTION` / `SINGLE_IMPLEMENTATION` / `DEAD_OR_LEGACY`) | 8 |
| Required repetitions recorded as `KEEP_REQUIRED` finding + section 7 | 1 finding + separate preserve list |
| Baseline integrity failures | 3 |
| `UNKNOWN_NEEDS_TRACE` | 0 in this first-pass set (remaining unknowns listed only as follow-on notes) |
| Total findings (cap 12) | 12 |

## 3. Baseline validator state

All four commands were source-inspected for write flags before execution. Each exposes only `--json` (or policy path for the Python audit) and was judged read-only. No `--write` / `--fix` / `--apply` / `--output` / `--render` options were used.

### 3.1 `ruby scripts/validate_harness_contract_version_registry.rb --json`

| Field | Value |
|---|---|
| Exit code | `1` |
| PASS/FAIL | **FAIL** |
| Core result | `contract_count=88`, `schema_file_count=112`, `active_schema_route_count=88`, `exact_duplicate_schema_groups=[]`, one error |
| Error summary | `reference_management_catalog: declared version "idol_reference_management_catalog.v2" is not present in schemas/reference-management-catalog.schema.json` |
| Diagnostic note | Emits `high_overlap_diagnostics` for 03V intake vs playback worklist (Jaccard 0.8). Per scripts/README and the validator itself, high-overlap is **diagnostic only**, not merge authority. |
| Classification | **BASELINE_INTEGRITY_FAILURE** (not an efficiency finding by itself) |

### 3.2 `ruby scripts/validate_harness_surface_version_registry.rb --json`

| Field | Value |
|---|---|
| Exit code | `1` |
| PASS/FAIL | **FAIL** |
| Core result | `surface_count=332`, `tracked_skill_count=33`, `skill_shape_review_count=3` |
| Error summary | 11 tracked surfaces have stale SHA-256 (wiki platform ops, video-sources README, reference-management catalog schema, reference-retrieval wiki pages, reference catalogs) |
| Classification | **BASELINE_INTEGRITY_FAILURE** |

### 3.3 `ruby scripts/idol_script_registry_check.rb --json`

| Field | Value |
|---|---|
| Exit code | `1` |
| PASS/FAIL | **FAIL** |
| Core result | `stale=[]`; `unmentioned` has 5 paths |
| Unmentioned | `scripts/lib/idol_api_video_quality.py`, `scripts/lib/idol_social_taxonomy.rb`, `scripts/validate_final_delivery_manifest.py`, `scripts/validate_founder_sequence_control.rb`, `scripts/validate_terra_section_lifecycle_receipt.rb` |
| Classification | **BASELINE_INTEGRITY_FAILURE** |

### 3.4 `python3 scripts/idol_instruction_surface_audit.py --json`

| Field | Value |
|---|---|
| Exit code | `0` |
| PASS/FAIL | **PASS** |
| Core result | `status=pass`, `errors=[]`; protected invariants all present; size warnings only |
| Warnings | AGENTS.md / maintenance rules / two startup profiles exceed word targets (diagnostic; remediation still Founder-explicit only) |
| Classification | Baseline integrity **PASS**; size warnings are not efficiency findings |

## 4. Validation call graph

Observed paths below were confirmed by reading the named scripts. No full production run was executed.

### 4.1 Official baseline (this audit)

```text
Operator
├─ ruby scripts/validate_harness_contract_version_registry.rb --json
│  ├─ YAML.safe_load automation/harness-contract-version-registry.yaml
│  ├─ read every registered schemas/*.schema.json (parse JSON, version string scan, $id uniqueness, content-hash groups, pairwise top-level Jaccard)
│  ├─ YAML.safe_load automation/harness-stage-registry.yaml (active stage output contracts)
│  └─ Dir.glob scripts/** + File.binread scan for schemas/*.schema.json refs (~228 files / ~5.8MB active tree this snapshot)
│  schema subprocess: none
│  same-input schema recheck: 0
│  mutation/trust boundary: none (read-only)
│  judgment: KEEP_REQUIRED as maintenance gate; SCOPE candidate when nested in every run check
│
├─ ruby scripts/validate_harness_surface_version_registry.rb --json
│  ├─ Open3: idol-video-python scripts/validate_json_schema.py
│  │         schemas/harness-surface-version-registry.schema.json
│  │         automation/harness-surface-version-registry.yaml
│  ├─ YAML.safe_load same registry file again
│  ├─ Digest::SHA256.file for each of 332 tracked surfaces
│  ├─ skill path coverage + line counts
│  └─ Dir.glob scripts/*.{rb,py} File.read for write-guard classification
│  same schema on same registry bytes: 1 (inside this entrypoint)
│  judgment: required for maintenance; expensive when nested hot
│
├─ ruby scripts/idol_script_registry_check.rb --json
│  ├─ git ls-files scripts (or glob fallback)
│  └─ parse scripts/README.md backtick refs
│  judgment: KEEP_REQUIRED maintenance inventory
│
└─ python3 scripts/idol_instruction_surface_audit.py --json
   ├─ automation/instruction-surface-policy.yaml
   └─ measured instruction surfaces only
   judgment: KEEP_REQUIRED instruction-policy audit; not nested in state_check harness group
```

### 4.2 Primary hot path: `idol_harness_state_check.rb RUN_ROOT`

```text
ruby scripts/idol_harness_state_check.rb RUN_ROOT [--json]
│  (always requires a run root; always executes harness group before run artifacts)
│
├─ [1] stage_registry_schema
│     idol-video-python validate_json_schema.py
│       schemas/harness-stage-registry.schema.json
│       automation/harness-stage-registry.yaml
│
├─ [2] stage_registry_semantics
│     ruby scripts/idol_harness_stage.rb validate
│       re-YAML-loads same stage registry; semantic ownership/alias rules
│       (does NOT re-run JSON Schema)
│
├─ [3] artifact_routing_semantics
│     ruby scripts/validate_harness_artifact_routing.rb
│       schema-validate harness-artifact-routing.yaml
│       re-YAML-loads stage registry for exact-cover cross-check
│
├─ [4] harness_execution_contract
│     validate_json_schema.py on automation/harness-execution-contract.yaml
│
├─ [5] harness_contract_version_registry
│     validate_json_schema.py on automation/harness-contract-version-registry.yaml
│
├─ [6] harness_contract_version_registry_semantics
│     ruby scripts/validate_harness_contract_version_registry.rb
│       re-YAML-loads same registry; full script tree binread; stage registry again
│       (does NOT re-run JSON Schema on the registry)
│     same-file schema+semantic: layered KEEP; full-repo scan SCOPE candidate
│
├─ [7] harness_surface_version_registry
│     validate_json_schema.py on automation/harness-surface-version-registry.yaml
│
├─ [8] harness_surface_version_registry_semantics
│     ruby scripts/validate_harness_surface_version_registry.rb
│       *** re-runs the same validate_json_schema.py on the same schema+file ***
│       then SHA-256 all 332 surfaces + script write-guard scan
│     same bytes / same schema / no mutation: CONSOLIDATE_CANDIDATE (pure duplicate of [7])
│
├─ [9] skill_path_contracts
│     ruby scripts/idol_skill_contract_check.rb  → scan skills/*/SKILL.md paths
│
├─ [10] skill_purpose_contract_matrix
│     ruby scripts/idol_skill_contract_matrix.rb --strict
│       re-scan skills/*/SKILL.md with near-duplicate path extraction helpers
│       builds full markdown report to stdout (write only if --write)
│
├─ [11] script_registry
│     ruby scripts/idol_script_registry_check.rb
│
├─ run-owned receipt / intervention / expert-gate / artifact validators...
│     (per-artifact schema then semantic; mostly KEEP_REQUIRED trust boundaries)
│
└─ final aggregate report (optional --write-report NOT used in this audit)

Repeat counts of note inside one state_check invocation:
- surface registry JSON Schema on identical bytes: 2 (checks [7]+[8])
- stage registry YAML load: ≥3 processes ([2],[3],[6]) after one schema load ([1])
- skills/* full text scan: 2 ([9]+[10])
- full scripts inventory: contract registry binread + script registry listing + surface write-guard reads
```

### 4.3 Wrappers around state_check

```text
ruby scripts/idol_harness_frontier_check.rb ...
├─ default: active frontier only (selective; avoids full scan)
└─ --full-audit → nests full idol_harness_state_check.rb --json
   judgment: selective default is KEEP_REQUIRED design; full-audit reintroduces F-EFF-02 cost deliberately

ruby scripts/idol_harness_refresh.rb RUN_ROOT
├─ dry-run (no --write): capture_state → state_check only
└─ --write: state_check + worklist writes + action queue + next unit + schema validate of written queues
   judgment: dry-run reuses state_check; --write path has intentional post-write revalidation (KEEP)
   NOT_RUN_WRITE_RISK: --write path not executed in this audit
```

### 4.4 Common leaf pattern (many stage validators)

```text
ruby scripts/validate_<stage>.rb ARTIFACT
├─ Open3 idol-video-python validate_json_schema.py SCHEMA ARTIFACT
└─ YAML.safe_load ARTIFACT again for semantic rules
same bytes, no mutation between steps, but different authority (schema vs semantic): KEEP_REQUIRED
process-level reparse cost: CACHE_CANDIDATE only if a shared in-process validated document API is introduced carefully
```

### 4.5 Call-graph summary table

| Entry | Nested validator | Schema | Artifact / scope | Same-check repeats | Mutation/trust boundary | Judgment |
|---|---|---|---|---:|---|---|
| state_check | validate_json_schema + surface semantic | surface-version registry schema | registry YAML | 2× schema | none | CONSOLIDATE |
| state_check | contract schema + contract semantic | contract-version registry schema | registry + all schemas + scripts/** | 1× schema; 1× full script scan | none | SCOPE (nesting), KEEP (layers) |
| state_check | stage schema + stage semantic + routing + contract | stage registry schema / none | stage registry | 1× schema; ≥3× YAML load | none | CACHE parse; KEEP semantics |
| state_check | skill_check + skill_matrix | n/a | all skills | 2× skill text scan | none | SINGLE_IMPL / SCOPE |
| frontier default | selective frontier | pointer artifacts | active frontier only | 0 full-repo | none | KEEP |
| frontier --full-audit | state_check | all of above | full harness + run | inherits state_check | none | intentional broad closeout |
| stage validators | schema + semantic | stage schema | one artifact | 1 each layer | consumer/readiness | KEEP |
| refresh --write | state_check then post-write schema | queue schemas | newly written queues | 2 epochs | post-write | KEEP / NOT_RUN |

## 5. Findings index

| ID | Classification | Priority | Confidence | Current state | Impact | Minimal owner | Applied |
|---|---|---|---|---|---|---|---|
| F01 | BASELINE_INTEGRITY_FAILURE | P0 | high | contract registry version string mismatch | maintenance gate FAIL | contract-version registry + owning schema maintainers | NOT_APPLIED |
| F02 | BASELINE_INTEGRITY_FAILURE | P0 | high | 11 stale surface SHA-256 rows | surface registry FAIL | surface-version registry maintainers | NOT_APPLIED |
| F03 | BASELINE_INTEGRITY_FAILURE | P1 | high | 5 scripts unmentioned in scripts/README.md | script registry FAIL | scripts/README.md registry owner | NOT_APPLIED |
| F04 | CONSOLIDATE_CANDIDATE | P0 | high | surface registry schema validated twice in one state_check | pure duplicate work | `idol_harness_state_check.rb` and/or surface validator ownership | NOT_APPLIED |
| F05 | SCOPE_REDUCTION_CANDIDATE | P0 | high | every run state_check runs full-repo maintenance suite | high frequency ops cost | state_check check grouping / profile owner | NOT_APPLIED |
| F06 | CACHE_CANDIDATE | P1 | high | stage registry reloaded in ≥3 nested tools per state_check | repeated parse of unchanged bytes | state_check orchestration or shared registry load helper | NOT_APPLIED |
| F07 | SINGLE_IMPLEMENTATION_CANDIDATE | P1 | high | skill path extraction duplicated in two checkers | drift risk + double skill scan | skill contract tooling owner | NOT_APPLIED |
| F08 | SCOPE_REDUCTION_CANDIDATE | P1 | high | surface semantic always hashes 332 surfaces + scans scripts | heavy maintenance cost on hot path | surface validator + when it is invoked | NOT_APPLIED |
| F09 | CACHE_CANDIDATE | P2 | medium | schema subprocess then Ruby re-YAML of same artifact | common process-boundary cost | validate_json_schema / shared validated-load helper | NOT_APPLIED |
| F10 | DEAD_OR_LEGACY_ROUTE_CANDIDATE | P2 | medium | INACTIVE_SHARED_SCRIPTS still present (~339KB+) | maintenance surface noise | script lifecycle / archive owner | NOT_APPLIED |
| F11 | SCOPE_REDUCTION_CANDIDATE | P2 | medium | docs list same validators as both nested and standalone | operator re-run of already-nested checks | scripts/README + maintenance docs routing | NOT_APPLIED |
| F12 | KEEP_REQUIRED | P3 | high | dual Ruby/Python integrity and run-layout libs | intentional cross-language parity; residual drift cost | lib owners (do not merge languages) | NOT_APPLIED |

## 6. Detailed findings

### F01 — Contract version registry baseline failure

- **Classification:** `BASELINE_INTEGRITY_FAILURE`
- **Current state:** Official validator exits 1.
- **Evidence:** Error string from `validate_harness_contract_version_registry.rb --json`: declared version `idol_reference_management_catalog.v2` not present in `schemas/reference-management-catalog.schema.json`.
- **Execution path:** direct official baseline command (also nested as state_check checks [5]+[6]).
- **Repeated work:** not the issue; integrity mismatch is.
- **Why not efficiency:** failure of declared version vs schema bytes is correctness debt.
- **Ops cost:** qualitative only — blocks maintenance green status until repaired under separate approval.
- **Minimal owner adjustment:** registry row and/or schema `$id`/enum string ownership; no efficiency redesign.
- **Quality/gate risk if “fixed” wrongly:** shipping a wrong version string without Founder/schema process would hide real drift.
- **Revalidation after future fix:** re-run contract registry validator; surface hash if schema file is tracked.
- **Change applied:** NO

### F02 — Surface version registry stale hashes

- **Classification:** `BASELINE_INTEGRITY_FAILURE`
- **Current state:** 11 tracked paths have SHA-256 drift vs current bytes.
- **Evidence:** validator errors for wiki platform credential ops, video-sources README, reference-management schema, reference-retrieval wiki set, reference catalogs.
- **Why not efficiency:** stale registry is integrity; hashing cost is separate (F08).
- **Change applied:** NO

### F03 — Script registry unmentioned files

- **Classification:** `BASELINE_INTEGRITY_FAILURE`
- **Current state:** five live script paths not mentioned in `scripts/README.md`.
- **Evidence:** `idol_script_registry_check.rb --json` `unmentioned` list.
- **Why not efficiency:** inventory completeness failure.
- **Change applied:** NO

### F04 — Double JSON-Schema validation of surface registry inside one state_check

- **Classification:** `CONSOLIDATE_CANDIDATE`
- **Priority / confidence:** P0 / high
- **Current state:** In a single `idol_harness_state_check.rb` invocation, the same schema and same registry file are validated twice with no intermediate mutation.
- **Exact locations:**
  - `scripts/idol_harness_state_check.rb` ~2000–2014: `add_schema_check` id `harness_surface_version_registry` then `add_command_check` id `harness_surface_version_registry_semantics`
  - `scripts/idol_harness_state_check.rb` `add_schema_check` (~666–694): builds `idol-video-python scripts/validate_json_schema.py SCHEMA ARTIFACT`
  - `scripts/validate_harness_surface_version_registry.rb` ~24–31: Open3 again to the same `validate_json_schema.py` + same schema + same registry
- **Call order:** state_check schema check → state_check launches surface semantic validator → surface validator re-runs schema → surface semantic hash/skill/guard rules
- **What repeats:** full JSON Schema validation of `automation/harness-surface-version-registry.yaml` against `schemas/harness-surface-version-registry.schema.json`
- **Same-input proof:**
  - same paths hard-coded in both layers
  - no write between checks in the semantic validator (read + hash only)
  - no external handoff or different schema version between [7] and [8]
- **Mutation / trust boundary:** none between the two schema runs; the second run does not add a new trust domain for schema shape
- **Why removable as pure schema duplicate:** the nested semantic validator already fails if schema validation fails; parent `add_schema_check` is redundant for schema shape only
- **What must still remain:** the semantic rules (per-surface SHA-256, skill coverage, write-guard) remain required
- **Ops cost:** qualitative only — extra Python/video-python process spawn + full schema validate on a large YAML document on every state_check
- **Minimal responsibility adjustment:** either (a) state_check drops the standalone schema check for this artifact and trusts the nested validator’s schema gate, or (b) surface validator gains a skip-schema flag used only by state_check after parent schema pass, with failure still blocking
- **Risks:** incorrect skip flag could allow semantic path to run on schema-invalid YAML if ordering is inverted; schema errors might surface only from one layer (message UX)
- **Revalidation after future change:** state_check JSON on a fixture run; direct surface validator alone; intentional schema-invalid registry fixture if present in tests
- **Change applied:** NO

### F05 — Run state_check always executes full-repo maintenance suite

- **Classification:** `SCOPE_REDUCTION_CANDIDATE`
- **Priority / confidence:** P0 / high
- **Current state:** `idol_harness_state_check.rb` requires `RUN_ROOT` but always runs repo-global harness checks before run-scoped artifact checks.
- **Exact locations:**
  - `scripts/idol_harness_state_check.rb` ~1939–2066 harness group: stage registry, routing, execution contract, contract registry (+semantics), surface registry (+semantics), video analysis registry, expert gate, skill contracts, skill matrix, script registry
  - No skip/fast/profile flag found for harness-only vs run-only partitioning
- **What repeats / over-scopes:** full maintenance validation of unchanging shared harness bytes on every run readiness poll
- **Same-input proof for the over-scope claim:** harness checks do not take the run path as input for registry validators (commands are repo-global); only later checks use `run_rel`
- **Mutation/trust boundary:** none requiring per-run rehash of all 332 instruction surfaces when only a run YAML changed
- **Why candidate:** frequency × scope mismatch. Registry integrity is necessary after harness edits; not necessarily on every section/run status poll
- **Why not delete entirely:** after harness edits, closeout, or release, full maintenance suite remains KEEP_REQUIRED
- **Ops cost:** qualitative only — highest frequency multiplier for F04/F06/F07/F08
- **Minimal responsibility adjustment:** introduce explicit profiles (e.g. `run_readiness` vs `harness_maintenance` vs `closeout_full`) owned by state_check; frontier already models selective vs full-audit
- **Risks:** an operator might skip maintenance too long and discover registry drift late; profile defaults must fail closed for closeout/release
- **Revalidation:** frontier default still selective; full-audit still nests full suite; maintenance CI/docs still call registry validators directly
- **Change applied:** NO

### F06 — Stage registry multi-load inside one state_check tree

- **Classification:** `CACHE_CANDIDATE`
- **Priority / confidence:** P1 / high
- **Current state:** one state_check path schema-validates the stage registry once, then at least three nested tools re-parse the same YAML for different semantic jobs.
- **Exact locations:**
  - state_check ~1944–1957: schema validate stage registry
  - `scripts/idol_harness_stage.rb` ~41+: `YAML.safe_load` + semantic validate
  - `scripts/validate_harness_artifact_routing.rb` ~53–57: loads stage registry for exact-cover
  - `scripts/validate_harness_contract_version_registry.rb` ~135+: loads stage registry for active output contracts
- **What repeats:** YAML parse of `automation/harness-stage-registry.yaml` (and process startups)
- **Same-input proof:** hard-coded default paths; no writer between harness checks
- **Why not merge the semantic rules:** stage ownership, routing exact-cover, and contract registration are distinct rule sets (KEEP separate implementations or shared pure functions)
- **Ops cost:** qualitative only — small YAML, but multi-process startup dominates more than parse CPU
- **Minimal adjustment:** optional shared “load stage registry once” orchestrator cache for a single parent process; do not collapse semantic ownership
- **Risks:** stale cache if a future parent mutates registry mid-run (today it does not)
- **Change applied:** NO

### F07 — Duplicated skill path-contract extraction and double skill scan

- **Classification:** `SINGLE_IMPLEMENTATION_CANDIDATE`
- **Priority / confidence:** P1 / high
- **Current state:** `idol_skill_contract_check.rb` and `idol_skill_contract_matrix.rb` both define nearly the same `PATH_PATTERN`, placeholder filters, and `candidate_paths` extraction; state_check runs both over all `skills/*/SKILL.md`.
- **Exact locations:**
  - `scripts/idol_skill_contract_check.rb` ~9–75 path helpers; ~85–134 full skill loop
  - `scripts/idol_skill_contract_matrix.rb` ~42–75 path helpers (parallel); ~130–175 skill loop
  - state_check ~2044–2057 both invoked
- **What repeats:** skill text reads + path candidate extraction; partially overlapping missing-heading checks
- **Same-input proof:** both glob `skills/*/SKILL.md` (matrix; check similar) with no mutation between state_check steps
- **Distinct value still present:** matrix adds mode classification (core/isolated/retired), output-boundary matrix, and optional markdown inventory; check focuses on readable path existence
- **Ops cost:** qualitative only — ~31 skills read twice per state_check; drift risk if one PATH_PATTERN is updated and the other is not
- **Minimal adjustment:** extract shared path-candidate helper used by both; optionally one command with submodes (`paths` / `matrix`) for state_check
- **Risks:** over-merging could drop matrix-only mode rules or check-only path resolution edge cases
- **Change applied:** NO

### F08 — Surface semantic validator always hashes entire tracked surface set

- **Classification:** `SCOPE_REDUCTION_CANDIDATE`
- **Priority / confidence:** P1 / high
- **Current state:** every invocation of `validate_harness_surface_version_registry.rb` SHA-256s all 332 surfaces and scans top-level scripts for write-guard classification.
- **Exact locations:**
  - `scripts/validate_harness_surface_version_registry.rb` ~45–48 per-surface `Digest::SHA256.file`
  - ~98–116 `Dir.glob scripts/*.{rb,py}` full-text write-operation scan
- **What repeats:** full-set hashing even when caller only needs “is registry structurally valid” or when only one surface changed
- **Same-input proof:** no path filter / changed-file filter flags in OptionParser (only `--json`)
- **Why still required sometimes:** maintenance patches that touch instruction surfaces must re-seal hashes; write-guard must remain global for classification completeness
- **Ops cost:** qualitative only — dominant cost node when nested via F05; 332 file hashes + multi-hundred script reads
- **Minimal adjustment:** optional changed-path or git-diff scope for local iteration; full mode remains default for CI/closeout; state_check profile decides when to call full mode
- **Risks:** partial hash check could miss unlisted drift if operators rely on partial mode for release
- **Change applied:** NO

### F09 — Schema subprocess then Ruby re-parse of the same artifact

- **Classification:** `CACHE_CANDIDATE`
- **Priority / confidence:** P2 / medium
- **Current state:** widespread Ruby validator pattern: Open3 to `validate_json_schema.py` (Python loads YAML/JSON), then Ruby `YAML.safe_load` of the same path for semantic rules.
- **Exact locations:** pattern present across many `scripts/validate_*.rb` and helpers (audit enumerated 40+ scripts with `validate_json_schema` + YAML load). Representative: surface validator ~24–32; artifact routing ~56–63 + `load_mapping`; stage validators generally.
- **What repeats:** disk read + parse of identical bytes in two runtimes
- **Same-input proof:** sequential in one parent process with no write between schema and semantic steps for pure validators
- **Why often KEEP:** language boundary and independent schema engine; semantic rules intentionally sit outside jsonschema
- **Why still a cache candidate:** a shared validated-load helper could return both “schema ok” and a parsed document once per process without removing either authority
- **Ops cost:** qualitative only — amplified by process spawn of `idol-video-python` for every small YAML
- **Minimal adjustment:** long-term shared library API; short-term no behavior change required
- **Risks:** diverging YAML loaders (Python UniqueKeyLoader vs Ruby Psych) must remain consistent; caching must not skip unique-key rejection
- **Change applied:** NO

### F10 — Inactive shared scripts still present as maintainable surface

- **Classification:** `DEAD_OR_LEGACY_ROUTE_CANDIDATE`
- **Priority / confidence:** P2 / medium
- **Current state:** `validate_harness_contract_version_registry.rb` lists `INACTIVE_SHARED_SCRIPTS` and excludes them from active schema-ref scanning, but the files remain in `scripts/` and some still have callers/tests/docs.
- **Exact locations:**
  - `scripts/validate_harness_contract_version_registry.rb` ~34–43 `INACTIVE_SHARED_SCRIPTS`
  - Present on disk this snapshot (sizes include `scripts/validate_video_prompt_index.rb` ~118KB and others; inactive set ≈339KB total)
  - Residual references: e.g. `scripts/idol_video_prompt_drive_sync.rb` still mentions `validate_video_prompt_index`; tests remain for some inactive helpers
- **What is inefficient:** continued inventory/test/doc gravity around routes declared inactive for authoring-schema registration
- **Not proven:** that every inactive script is unreachable at runtime; some may still be historical operators
- **Ops cost:** qualitative only — human maintenance and registry noise more than CPU
- **Minimal adjustment:** archive policy / explicit “historical only” section in scripts/README; do not mass-delete without Founder cleanup plan and reverse-reference check (`wiki/artifact-management-system.md`)
- **Risks:** deleting a still-used historical recovery tool; false “dead” labeling
- **Change applied:** NO

### F11 — Multiple documentation entrypoints for the same maintenance validators

- **Classification:** `SCOPE_REDUCTION_CANDIDATE`
- **Priority / confidence:** P2 / medium
- **Current state:** the same validators appear both as nested state_check checks and as standalone mandatory/common commands in operator docs.
- **Exact locations:**
  - `scripts/README.md` documents `idol_harness_state_check.rb`, `validate_harness_contract_version_registry.rb`, `validate_harness_surface_version_registry.rb`, `idol_script_registry_check.rb`, `idol_instruction_surface_audit.py` as primary tools
  - `wiki/harness-maintenance-rules.md` ~222: run `python3 scripts/idol_instruction_surface_audit.py` after structural instruction changes
  - state_check already nests contract/surface/script registry (but not instruction-surface audit)
- **What is inefficient:** operators can re-run the same full-repo validators after a state_check that already executed them, without a clear “already covered by state_check harness group” map
- **Same-input proof:** docs recommend direct invocation; state_check command list hard-codes the same scripts
- **Not a code defect:** standalone entrypoints remain necessary for harness-only maintenance without a run root
- **Ops cost:** qualitative only — human time and repeated multi-minute/full-tree scans
- **Minimal adjustment:** documentation routing table: “after harness edit → maintenance suite”; “during run production → run readiness / frontier”; “closeout → full-audit”
- **Risks:** over-suppressing standalone runs after real harness edits
- **Change applied:** NO

### F12 — Dual Ruby/Python integrity and run-layout libraries (preserve)

- **Classification:** `KEEP_REQUIRED`
- **Priority / confidence:** P3 / high
- **Current state:** `scripts/lib/idol_artifact_integrity.{rb,py}` and `scripts/lib/idol_run_layout.{rb,py}` intentionally provide parallel APIs; README states shared policy across Ruby and Python consumers.
- **Why it looks like duplication:** two implementations of hash cache profiles and run identity validation
- **Why required:** Ruby and Python validators cannot share one runtime without large rewrites; language-local libs prevent each script re-implementing hash policy
- **Residual risk:** implementation drift between RB/PY (future UNKNOWN if no parity tests are continuous)
- **Minimal adjustment:** keep dual surfaces; strengthen shared contract tests rather than merging languages
- **Change applied:** NO

## 7. Required repetitions to preserve

These look repetitive but must not be removed as “duplicate efficiency wins.”

| Pattern | Why required | What breaks if removed |
|---|---|---|
| JSON Schema check then separate semantic validator with different rules | schema shape ≠ ownership/hash/path/exact-cover rules | semantic-only false confidence or schema-only incomplete gates |
| state_check schema of contract registry + contract semantic (no nested re-schema) | layered authority already mostly clean | n/a for consolidation; keep layers |
| Producer validate then consumer re-validate | different trust boundary and later stage advancement | TOCTOU / stale artifact advancement |
| Pre-write vs post-write validation (refresh --write, apply helpers) | bytes change at write boundary | accepting unwritten or half-written artifacts |
| Frontier selective vs `--full-audit` nesting state_check | closeout needs broad audit; daily frontier should stay narrow | either constant full-repo cost or missing closeout coverage |
| Pixel / playback / Founder / skill-application receipts after schema | creative and evidence authority are not schema | schema-pass creative false green |
| Dual RB/PY integrity helpers | language boundary | divergent hash policy per language |
| `high_overlap_diagnostics` without merge | similarity is not authority | accidental schema merge against harness invariants |

## 8. Recommended correction order

Do not execute these here. Order only if a future Founder-approved efficiency maintenance task exists.

### Fast / lower risk (after separate approval)

1. Remove pure double surface schema validation in the state_check tree (F04) while keeping surface semantic rules.
2. Document operator entrypoint routing so maintenance validators are not re-run after an already-full state_check (F11).
3. Extract shared skill path-candidate helper used by both skill checkers (F07).

### Call-graph cleanup first

4. Introduce state_check profiles: run readiness vs harness maintenance vs closeout full (F05), aligning with frontier’s selective/full-audit model.
5. Decide when surface full-hash mode is mandatory vs optional scoped mode (F08), only after F05 profile design.

### Higher quality / gate risk

6. Any partial hashing or skip-schema flags (F04/F08/F09) need failure-mode tests so release/closeout cannot silently skip.
7. Inactive script lifecycle (F10) requires reverse-reference-checked Founder cleanup plan; not a drive-by delete.

### Needs separate Founder decision

8. Baseline integrity repairs (F01–F03) are not efficiency work; they need ordinary registry/schema ownership and must not be bundled as “efficiency.”
9. Any change that weakens always-on maintenance during production requires explicit Founder acceptance of detection latency for harness drift.

## 9. Reproduction checklist for Codex

### Shared setup

- Root: `/Users/yuminseog/aheyabaraya_hq_root/hq-control/creative/IDOL`
- Read-only only; do not pass write flags
- Expect baseline FAIL on F01–F03 until separately repaired

### F01

- Files: `scripts/validate_harness_contract_version_registry.rb`; registry row for `reference_management_catalog`; `schemas/reference-management-catalog.schema.json`
- Command: `ruby scripts/validate_harness_contract_version_registry.rb --json`
- Expect: exit 1; version string error
- Counterexample: if schema contains the declared version string, finding is stale
- Invariant: scripts never author creative truth; registry version must match schema-declared version set

### F02

- Files: `scripts/validate_harness_surface_version_registry.rb`; `automation/harness-surface-version-registry.yaml`
- Command: `ruby scripts/validate_harness_surface_version_registry.rb --json`
- Expect: exit 1; multiple `tracked surface SHA-256 is stale`
- Counterexample: if all hashes match current bytes, finding is stale

### F03

- Files: `scripts/idol_script_registry_check.rb`; `scripts/README.md`
- Command: `ruby scripts/idol_script_registry_check.rb --json`
- Expect: five unmentioned paths listed in this audit (or a non-empty unmentioned set)
- Counterexample: empty unmentioned + empty stale ⇒ baseline pass

### F04

- Files/symbols: `idol_harness_state_check.rb` ids `harness_surface_version_registry` and `harness_surface_version_registry_semantics`; `validate_harness_surface_version_registry.rb` Open3 schema block
- Read-only command: static read; optionally `rg -n "validate_json_schema.py" scripts/idol_harness_state_check.rb scripts/validate_harness_surface_version_registry.rb`
- Expect: parent schema check path and nested validator both name the same schema + registry
- Counterexample: if nested validator no longer calls schema, or parent no longer schema-checks surface registry, consolidate candidate is resolved or inverted
- Invariant: schema validity still required before treating registry as authoritative

### F05

- Files: `scripts/idol_harness_state_check.rb` harness group ~1939–2066; usage requiring RUN_ROOT
- Command: static inspection; do not need to run full state_check for proof
- Expect: repo-global validators invoked without run path arguments before run artifact checks; no run-only profile flag
- Counterexample: presence of an explicit profile that skips harness group for run readiness

### F06

- Files: `idol_harness_stage.rb`, `validate_harness_artifact_routing.rb`, `validate_harness_contract_version_registry.rb` stage registry loads
- Expect: ≥3 independent loads of `automation/harness-stage-registry.yaml` in the state_check tree
- Counterexample: single shared load orchestrated by parent

### F07

- Files: path helpers in `idol_skill_contract_check.rb` and `idol_skill_contract_matrix.rb`; state_check skill checks
- Expect: duplicated `PATH_PATTERN` / `candidate_paths`; both executed in harness group
- Counterexample: shared library require; single skill contract entrypoint

### F08

- Files: surface validator SHA loop and script write-guard scan
- Command: `ruby scripts/validate_harness_surface_version_registry.rb --json` (also demonstrates baseline F02)
- Expect: processes all surfaces; no path filter option
- Counterexample: `--only` / changed-path mode exists

### F09

- Files: any representative `validate_*.rb` with SCHEMA_VALIDATOR + YAML.safe_load
- Expect: Open3 schema then Ruby reparse
- Counterexample: shared validated document returned once per process

### F10

- Files: `INACTIVE_SHARED_SCRIPTS` constant; disk presence of listed scripts
- Expect: files exist while excluded from active schema-ref registration
- Counterexample: inactive list empty or files archived out of active scripts/

### F11

- Files: `scripts/README.md` registry sections; `wiki/harness-maintenance-rules.md` instruction audit instruction; state_check nested commands
- Expect: same validators recommended standalone and nested without exclusive routing table
- Counterexample: docs clearly partition maintenance vs run readiness entrypoints

### F12

- Files: `scripts/lib/idol_artifact_integrity.rb`, `scripts/lib/idol_artifact_integrity.py`, run_layout twins; `scripts/README.md` shared library note
- Expect: intentional dual language policy text
- Counterexample: single-language only with no dual consumers

## 10. Codex independent verification

```yaml
verification_status: COMPLETE
verifier_surface: codex
verified_at: 2026-08-02T21:34:28+09:00
verified_branch: main
verified_commit: 3ce8927fe652c7429edfd165ec8b0b1cc6ec21b1
grok_handoff_sha256: 6b069d2af95336f7d246a45d5faa29e1860fd8268429cf2e32456a6ea2063c87
finding_results:
  confirmed: 6
  partial: 4
  rejected: 2
  not_reproducible: 0
mutation_scope: codex_verification_section_only
implementation_authorized: false
```

The Grok-owned header retains `codex_verification_pending: true` as the immutable
handoff snapshot. This section is the later sequential-owner verification and
supersedes that pending state without rewriting Grok's findings.

### 10.1 Verification method and state protection

- The handed-off report SHA-256 matched exactly before review:
  `6b069d2af95336f7d246a45d5faa29e1860fd8268429cf2e32456a6ea2063c87`.
- Before any Codex write, the worktree still contained `1523` porcelain rows and
  matched SHA-256
  `e0ed459a9b5e40f25030cee6e477a8bab358d05d27e6363402c70de426d6e2d9`.
  That is the post-Grok state: the pre-existing 1522 rows plus this report.
- Codex reran the four official read-only baseline commands, inspected every
  named call site, traced current operator routing, and ran a read-only active
  frontier check plus one read-only broad state check on
  `runs/2026-07-29/0729_ONE_MOVE`.
- Immediately before this section was written, the worktree fingerprint was
  still unchanged and the report still matched the Grok handoff SHA-256.
- No schema, registry, policy, skill, validator, script, wiki page, run artifact,
  queue, pointer, or creative truth was changed. No proposed fix was applied.

### 10.2 Independent result table

| ID | Codex result | Corrected priority / disposition | Independent basis |
|---|---|---|---|
| F01 | **CONFIRMED** | Baseline hold; keep separate from efficiency work | The official contract-version validator again exited 1. The registry declares `idol_reference_management_catalog.v2`, while the schema and current catalog use v3. The registry, schema, and catalog are all already modified in the pre-existing dirty worktree, so this verifies current failure only—not the intent or final repair for that in-progress work. |
| F02 | **CONFIRMED** | Baseline hold; keep separate from efficiency work | The surface validator again returned the same 11 stale SHA-256 paths. All named drift paths are already modified in the dirty worktree. This is current-byte integrity failure, not proof that the edits are wrong or abandoned. |
| F03 | **CONFIRMED** | Baseline hold; keep separate from efficiency work | The script registry checker again returned exactly five unmentioned paths and no stale references. `scripts/README.md` is already modified, so this remains an in-progress inventory closeout issue rather than efficiency evidence. |
| F04 | **CONFIRMED** | Downgrade from P0 to **P2, low-cost exact duplicate** | `idol_harness_state_check.rb` schema-validates the surface registry and then invokes `validate_harness_surface_version_registry.rb`, which validates the identical schema/file again before semantic checks. No mutation occurs between them. Warm read-only samples put the extra schema subprocess near 0.06 seconds, while one broad state check took about 16.87 seconds; the duplicate is real but not a P0 cost driver. Keep one schema gate and all semantic hash/coverage/write-guard checks if a later patch is approved. |
| F05 | **PARTIAL** | Replace P0 fix with **usage trace first** | The broad state checker does unconditionally run repository-wide harness checks, and one read-only sample took about 16.87 seconds. However, current `scripts/README.md` explicitly labels it a broad historical reporter and routes ordinary low-latency checks through `idol_harness_frontier_check.rb`; the active frontier inspected three selected paths in 216 ms with zero unrelated files. Therefore “every run readiness poll” is not established. The remaining question is whether `idol_harness_refresh.rb`, which still calls the broad checker, is used frequently enough to warrant rerouting. Do not add state-check profiles without that evidence. |
| F06 | **PARTIAL** | Downgrade to **P3 / benchmark before design** | Three independent subprocesses do reload the same 12,081-byte stage registry for distinct stage, routing, and contract semantics. The observation is correct, but a shared in-memory cache cannot cross those process boundaries without changing interfaces or combining owners. No measured benefit supports the proposed cache yet; keep the semantic checks separate and benchmark before treating this as actionable. |
| F07 | **CONFIRMED** | Downgrade to **P2 maintenance-drift candidate** | Both skill tools independently implement `PATH_PATTERN`, placeholder filtering, normalization, candidate extraction, and a full `skills/*/SKILL.md` read. Their patterns have already drifted slightly: the path checker includes `business-marketing`, while the matrix does not. A future shared pure extraction helper is reasonable, but the two validators' distinct existence/path and purpose/output rules must remain separate. |
| F08 | **PARTIAL** | No standalone validator-scope change; subsume caller concern under F05 | The surface validator does hash all 332 tracked surfaces and scan top-level scripts, exactly as reported. That is also its defined full current-state integrity contract. A changed-path mode is not equivalent and could miss undeclared drift. If frequent broad invocation is proven, optimize which caller invokes the full validator; do not weaken the validator's default coverage. |
| F09 | **REJECTED** | Reclassify as **KEEP_REQUIRED under current architecture** | Forty-nine Ruby scripts text-match both schema-validator invocation and YAML loading, but that does not prove every match reparses the same artifact. In verified representatives, Python enforces JSON Schema plus duplicate-key rejection, while Ruby needs its own parsed object for semantic rules. A Python process cannot hand Ruby an in-memory parsed object; serialization would still require another parse and a larger interface change. No safe cache win or timing evidence was established. |
| F10 | **PARTIAL** | Keep as **per-script reachability audit**, not a dead-route cleanup ticket | The nine `INACTIVE_SHARED_SCRIPTS` files exist and total 339,123 bytes, and several are explicitly documented as historical. They are not proven dead: tests, registries, guards, handoff docs, and residual callers remain; notably `idol_founder_pass_harness.rb` can still call `idol_grok_imagine_drive_sync.py` behind an option even though current docs call that route inactive. A future audit must classify each file separately and perform reverse-reference checks. No archive, move, or deletion is currently justified. |
| F11 | **REJECTED** | No documentation change supported | Current documentation already provides the proposed routing distinction: `scripts/README.md` labels `idol_harness_state_check.rb` broad/historical, labels `idol_harness_frontier_check.rb` the default low-latency preflight, and limits `--full-audit` to explicit harness/release closeout. Standalone registry validators are correctly documented for maintenance without a run root. `idol_instruction_surface_audit.py` is separately required after structural instruction edits and is not nested in state check. No evidence showed operators being instructed to run the same suite twice. |
| F12 | **CONFIRMED** | Preserve | Ruby and Python run-layout/integrity libraries have real consumers in both runtimes, and `scripts/README.md` explicitly assigns them the shared policy role. Do not merge languages. No continuous cross-language parity test was found in this review; a bounded parity-test proposal may be considered separately, but it is not a removal or consolidation finding. |

### 10.3 What remains worth considering

Only two bounded implementation candidates survive this review without needing
another discovery pass, and neither is authorized here:

1. **F04:** remove one of the two identical surface-registry schema invocations
   while retaining direct-validator schema safety and every semantic check. This
   is exact but low impact.
2. **F07:** place shared skill-path extraction in one pure helper while retaining
   the two distinct validator responsibilities. This primarily prevents drift,
   not large runtime cost.

The following need evidence before they become change tickets:

- Trace actual use and required authority of `idol_harness_refresh.rb` before
  changing broad-versus-frontier routing (F05).
- Benchmark the stage-registry subprocess chain before designing a cache or
  interface change (F06).
- If broad invocation is proven excessive, change caller routing rather than
  weakening full surface-integrity coverage (F08).
- Build a per-file reachability and reverse-reference matrix for the nine
  inactive/historical scripts before any lifecycle proposal (F10).

F01-F03 are current baseline failures inside pre-existing modified work and must
be closed by their owning workstreams. F09 and F11 should not enter an efficiency
backlog on the present evidence. No finding authorizes implementation, deletion,
registry resealing, stage advancement, or Founder PASS.

### 10.4 Concurrent worktree change observed after verification

After the Codex section was written, the porcelain row count remained `1523`
but its fingerprint changed from
`e0ed459a9b5e40f25030cee6e477a8bab358d05d27e6363402c70de426d6e2d9` to
`87516de4926150b292099242f6611953306ab08f68444ba828ac92632132a92e`.
Branch and commit stayed unchanged. Files updated during that window include
`source-materials/video-sources/READ-FIRST.md`,
`source-materials/video-sources/reference-analysis-registry.yaml`,
`source-materials/video-sources/reference-hub-catalog.yaml`, and a new
`tBMbAyqOLY8` source/contact-sheet lineage. The commands used by this verification
were read-only and did not target or write those files; the invoked registry
`verify` command also contains no write path. Codex treated this as concurrent
external work, did not inspect it as part of the efficiency finding set, and did
not revert or normalize it. Any later implementation pass must refresh the
baseline validators against the then-current bytes.

## 11. Final non-mutation attestation

| Item | Value |
|---|---|
| Start branch | `main` |
| Start commit | `3ce8927fe652c7429edfd165ec8b0b1cc6ec21b1` |
| Start porcelain line count | `1522` |
| Start porcelain SHA-256 | `e5045e3aa1a25a9bc81402e603f44a5b2e67127ec86ab2ee6e62367cf05779c7` |
| Report path before audit | absent |
| Allowed write | `automation/state-reports/grok-harness-efficiency-audit.md` only |
| End branch | `main` |
| End commit | `3ce8927fe652c7429edfd165ec8b0b1cc6ec21b1` |
| End porcelain line count | `1523` |
| End porcelain SHA-256 | `bd5968752619e23d377c5df6661c5f5abdfaefd491112d4555e90a71672b8bec` |
| End attestation time (UTC) | `2026-08-02T12:24:31Z` |
| Porcelain delta | exactly one new untracked path: `?? automation/state-reports/grok-harness-efficiency-audit.md` |
| Removed/changed pre-existing porcelain lines | `0` |

Grok attestation statements:

- Grok did not modify existing harness files, schemas, policies, skills, validators, registries, or wiki pages.
- Grok did not stage, commit, push, stash, reset, checkout, or branch-switch.
- Grok did not run write-capable flags, generation, external network, MCP mutation, CF harness, or subagents.
- Grok did not reverse or clean the pre-existing dirty worktree.
- Concurrent external dirty paths (pre-existing 1522 porcelain entries) were left untouched; only observation that they pre-existed is recorded.
- End fingerprint differs from start only by the allowed report file; audit mutation policy is satisfied.
- `CODEX_VERIFICATION_PENDING` remains true; this report has `no_gate_effect`.

### Commands intentionally not run (write risk or out of scope)

| Command / class | Reason |
|---|---|
| `idol_harness_state_check.rb` full run | requires a run root; broad and may be used with `--write-report`; not needed for static nested-call proof |
| `idol_harness_refresh.rb --write` | writes reports/queues | `NOT_RUN_WRITE_RISK` |
| `idol_skill_contract_matrix.rb --write` | writes automation markdown | `NOT_RUN_WRITE_RISK` |
| Full test suite / production flow | out of scope |
| Any `--fix` / `--apply` / paid generation | forbidden |

---

End of diagnostic report.
