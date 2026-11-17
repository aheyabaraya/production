"use strict";

const $ = (selector) => document.querySelector(selector);
const MODES = new Set(["peek", "compact", "expanded"]);

const WORKER_LABELS = {
  prepared: "준비",
  launched: "실행 등록",
  returned: "반환",
  reviewed: "검토됨",
  promoted: "승격",
  hold: "HOLD",
  retired: "종료",
  replaced: "대체됨",
  unknown: "미확인",
};

let operationsState = null;
let selectedFamilyId = null;
let selectedRunId = null;

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDateTime(value, fallback = "미확인") {
  if (!value) return fallback;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return fallback;
  return new Intl.DateTimeFormat("ko-KR", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(parsed);
}

function shortRunName(run) {
  const id = String(run?.run_id || "—");
  const revision = id.match(/_R(\d+)$/i);
  if (revision) return `R${revision[1]}`;
  if (/_GENERATE_\d{8}$/i.test(id)) return "GEN 01";
  const chunks = id.split("_").filter(Boolean);
  return chunks.length > 2 ? chunks.slice(-2).join(" ") : id;
}

function deadlineBadge(deadline) {
  return `<div class="deadline-badge ${escapeHTML(deadline?.state || "unknown")}">
    ${escapeHTML(deadline?.day_label || "—")}
    <small>${escapeHTML(deadline?.days ? `${deadline.days} DAY RUN` : "UNKNOWN")}</small>
  </div>`;
}

function currentFamily() {
  const families = operationsState?.mv_families || [];
  return families.find((family) => family.family_id === selectedFamilyId) || families[0] || null;
}

function currentRun(family = currentFamily()) {
  if (!family) return null;
  return family.runs.find((run) => run.run_id === selectedRunId) || family.runs[0] || null;
}

function notifyNative(mode) {
  const handler = window.webkit?.messageHandlers?.panelMode;
  if (handler) handler.postMessage({ mode });
}

function setMode(mode, notify = true) {
  const safeMode = MODES.has(mode) ? mode : "compact";
  document.body.dataset.mode = safeMode;
  if (operationsState) renderSelected();
  if (notify) notifyNative(safeMode);
}

function renderPeek(family, run) {
  $("#peek-role").textContent = run?.presentation_label || "MV";
  $("#peek-run-id").textContent = family ? `${family.title_key.toUpperCase()} · ${shortRunName(run)}` : "run 없음";
  $("#peek-family-count").textContent = family ? `${family.open_run_count} RUN FAMILY` : "—";
  $("#peek-deadline").textContent = run?.deadline?.day_label || "—";
  const attention = run?.worker_projection?.urgent?.length || 0;
  $("#peek-attention").textContent = `${attention} 확인`;
}

function renderFamilyBoard(families) {
  const totalRuns = families.reduce((sum, family) => sum + (family.open_run_count || 0), 0);
  $("#open-run-count").textContent = `${families.length} FAMILY · ${totalRuns} RUN`;
  $("#family-board").innerHTML = families.length ? families.map((family) => {
    const selected = family.family_id === selectedFamilyId;
    const relationship = family.relationship_basis === "shared_previous_run_root" ? "LINEAGE" : "TITLE";
    return `<button class="family-card ${selected ? "is-selected" : ""}" type="button" data-family-id="${escapeHTML(family.family_id)}">
      <span class="family-card-top"><strong>${escapeHTML(family.title_key.toUpperCase())}</strong><i>${escapeHTML(family.deadline?.day_label || "—")}</i></span>
      <span class="family-card-meta">${escapeHTML(family.open_run_count)} RUN · ${escapeHTML(family.worker_summary?.registered_heads || 0)} HEAD</span>
      <span class="family-card-foot">${escapeHTML(relationship)} · ${escapeHTML(family.worker_summary?.attention || 0)} 확인</span>
    </button>`;
  }).join("") : `<div class="empty-copy">표시 가능한 열린 MV family가 없습니다.</div>`;
}

function renderFamily(family) {
  if (!family) {
    $("#family-title").textContent = "열린 MV 없음";
    $("#run-switcher").innerHTML = "";
    $("#base-run").innerHTML = "";
    return;
  }
  $("#family-kicker").textContent = `${family.open_run_count} OPEN RUN · TRACKER VIEW`;
  $("#family-title").textContent = family.title_key.toUpperCase();
  $("#family-relationship").textContent = family.relationship_basis === "shared_previous_run_root" ? "같은 기준에서 분기" : "같은 타이틀 묶음";
  $("#run-switcher").innerHTML = family.runs.map((run) => {
    const projection = run.worker_projection || {};
    const selected = run.run_id === selectedRunId;
    return `<button class="run-tab ${run.presentation_role} ${selected ? "is-selected" : ""}" type="button" data-run-id="${escapeHTML(run.run_id)}">
      <span>${escapeHTML(run.presentation_label)}</span>
      <strong>${escapeHTML(shortRunName(run))}</strong>
      <small>${escapeHTML(projection.counts?.registered_heads || 0)} HEAD · ${escapeHTML(projection.urgent?.length || 0)} 확인</small>
    </button>`;
  }).join("");
  $("#base-run").innerHTML = family.base_run
    ? `<span>BASE · 기준 run</span><strong>${escapeHTML(family.base_run.run_id)}</strong><small>작업 분기 수에서 제외 · 접어서 보관</small>`
    : `<span>BASE</span><strong>별도 기준 run 없음</strong><small>같은 타이틀 묶음으로 표시</small>`;
}

function renderRun(run) {
  const target = $("#run-hero");
  target.classList.remove("skeleton-block");
  if (!run) {
    target.innerHTML = `<span class="hero-kicker">MV RUN</span><h1>현재 run을 찾지 못했습니다</h1><p class="run-path">표시 가능한 manifest 없음</p>`;
    return;
  }
  target.innerHTML = `
    <div class="hero-top">
      <div>
        <span class="hero-kicker">${escapeHTML(run.presentation_label)} · ${escapeHTML(run.status).toUpperCase()} · 표시 역할</span>
        <h1>${escapeHTML(run.run_id)}</h1>
      </div>
      ${deadlineBadge(run.deadline)}
    </div>
    <p class="run-path">${escapeHTML(run.root)}</p>
    <div class="hero-meta">
      <span>TITLE<strong>${escapeHTML(run.title_key)}</strong></span>
      <span>SEQ<strong>${escapeHTML(run.run_sequence)}</strong></span>
      <span>START<strong>${escapeHTML(formatDateTime(run.created_at))}</strong></span>
    </div>`;
}

function renderWorkers(projection) {
  const counts = projection?.counts || {};
  const metrics = [
    ["현재 HEAD", counts.registered_heads || 0, "total"],
    ["실행 등록", counts.launched || 0, "launched"],
    ["검토 대기", (counts.returned || 0) + (counts.reviewed || 0), "returned"],
    ["HOLD", counts.hold || 0, "hold"],
  ];
  $("#worker-metrics").innerHTML = metrics.map(([label, value, className]) => `
    <div class="worker-metric ${className}"><span>${escapeHTML(label)}</span><strong>${escapeHTML(value)}</strong></div>
  `).join("");
  $("#projection-note").textContent = projection
    ? `${projection.note} · 과거 attempt ${counts.history_attempts || 0}개 접힘 · 활동 자체는 별도 검증`
    : "등록된 worker projection이 없습니다.";

  const limit = document.body.dataset.mode === "expanded" ? 6 : 1;
  const urgent = projection?.urgent?.slice(0, limit) || [];
  $("#attention-count").textContent = projection?.urgent?.length || 0;
  $("#attention-list").innerHTML = urgent.length ? urgent.map((worker) => {
    const scope = [worker.stage_id, ...(worker.section_ids || [])].filter(Boolean).join(" · ");
    return `<article class="attention-item">
      <i class="state-mark ${escapeHTML(worker.execution_state)}"></i>
      <div class="attention-copy">
        <strong>${escapeHTML(worker.dispatch_id)}</strong>
        <span>${escapeHTML(scope || worker.role)} · ${escapeHTML(worker.attention_reason || "상태 확인")}</span>
      </div>
      <span class="state-label">${escapeHTML(WORKER_LABELS[worker.execution_state] || worker.execution_state)}</span>
    </article>`;
  }).join("") : `<div class="empty-copy">현재 attention queue가 비어 있습니다.</div>`;
}

function renderDeadlines(mv, cf) {
  const runs = [["MV", mv], ["CF", cf]];
  $("#deadline-strip").innerHTML = runs.map(([kind, run]) => {
    if (!run) return `<div class="deadline-row"><span>${kind}</span><div class="deadline-copy"><strong>run 미확인</strong><span>폴더 또는 manifest 없음</span></div><strong>—</strong></div>`;
    return `<div class="deadline-row">
      <span>${kind}</span>
      <div class="deadline-copy"><strong>${escapeHTML(run.run_id)}</strong><span>${escapeHTML(formatDateTime(run.deadline?.at))} · ${escapeHTML(run.created_at_source)}</span></div>
      <strong class="${escapeHTML(run.deadline?.state || "unknown")}">${escapeHTML(run.deadline?.day_label || "—")}</strong>
    </div>`;
  }).join("");
}

function renderSelected() {
  const families = operationsState?.mv_families || [];
  const family = currentFamily();
  if (family && family.family_id !== selectedFamilyId) selectedFamilyId = family.family_id;
  const run = currentRun(family);
  if (run && run.run_id !== selectedRunId) selectedRunId = run.run_id;
  renderPeek(family, run);
  renderFamilyBoard(families);
  renderFamily(family);
  renderRun(run);
  renderWorkers(run?.worker_projection);
  renderDeadlines(run, operationsState?.selected_cf_run);
}

async function refresh() {
  const response = await fetch("/api/state", { cache: "no-store" });
  const payload = await response.json();
  if (!response.ok || payload.ok === false) throw new Error((payload.details || ["상태를 불러오지 못했습니다."]).join(" · "));
  operationsState = payload.derived.operations;
  if (!selectedFamilyId) selectedFamilyId = operationsState.selected_mv_family_id;
  renderSelected();
  $("#updated-at").textContent = `UPDATED ${formatDateTime(operationsState.generated_at, "—")}`;
  $("#error-banner").classList.remove("is-visible");
}

async function safeRefresh() {
  try {
    await refresh();
  } catch (error) {
    const banner = $("#error-banner");
    banner.textContent = error.message;
    banner.classList.add("is-visible");
  }
}

document.addEventListener("click", (event) => {
  const modeButton = event.target.closest("[data-mode-target]");
  if (modeButton) {
    setMode(modeButton.dataset.modeTarget);
    return;
  }
  const familyButton = event.target.closest("[data-family-id]");
  if (familyButton) {
    selectedFamilyId = familyButton.dataset.familyId;
    selectedRunId = null;
    renderSelected();
    return;
  }
  const runButton = event.target.closest("[data-run-id]");
  if (runButton) {
    selectedRunId = runButton.dataset.runId;
    renderSelected();
  }
});

$("#refresh").addEventListener("click", safeRefresh);
const initialMode = new URLSearchParams(window.location.search).get("mode");
setMode(initialMode || "compact", false);
safeRefresh();
setInterval(() => { if (!document.hidden) safeRefresh(); }, 60_000);
