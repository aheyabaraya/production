"use strict";

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const PROJECT_STATUSES = {
  baseline_pending: "기준선 대기",
  planned: "계획",
  in_progress: "진행 중",
  waiting: "대기",
  review: "검토",
  completed: "완료",
  canceled: "취소",
};

const HEALTH_STATUSES = {
  unknown: "미확정",
  on_track: "정상",
  attention: "점검 필요",
  blocked: "막힘",
};

const MILESTONE_STATUSES = {
  not_started: "시작 전",
  in_progress: "진행 중",
  waiting: "대기",
  review: "검토",
  completed: "완료",
  canceled: "취소",
};

const GATE_STATUSES = {
  pending: "PENDING",
  pass: "PASS",
  hold: "HOLD",
  reject: "REJECT",
  not_required: "NOT REQUIRED",
};

const DECISION_STATUSES = {
  pending: "결정 대기",
  approved: "승인",
  held: "보류",
  rejected: "기각",
  superseded: "대체됨",
};

const EXECUTION_STATUSES = {
  queued: "대기열",
  running: "실행 중",
  waiting_for_input: "입력 대기",
  awaiting_review: "검토 대기",
  completed: "반환 완료",
  blocked: "막힘",
  failed: "실패",
  canceled: "취소",
};

const RESULT_STATES = {
  unverified: "미검증",
  verified: "검증됨",
  hold: "HOLD",
  rejected: "REJECT",
};

const VIEW_LABELS = {
  overview: ["IDOL REPOSITORY", "전체 현황"],
  projects: ["PORTFOLIO", "프로젝트"],
  timeline: ["SCHEDULE", "일정"],
  decisions: ["FOUNDER AUTHORITY", "Founder 결정"],
  executions: ["AI DELEGATION", "AI 작업"],
  workers: ["MV DISPATCH READ MODEL", "MV 작업자"],
  sources: ["SOURCE HEALTH", "원본·신뢰도"],
};

const WORKER_STATES = {
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

let trackerState = null;
let activeView = "overview";
let activeProjectId = null;
let laneFilter = "all";
let projectSearch = "";
let workerStateFilter = "all";
let workerSearch = "";
let pendingConfirmation = null;
let toastTimer = null;

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function clamp(value, minimum = 0, maximum = 100) {
  const number = Number(value);
  if (!Number.isFinite(number)) return minimum;
  return Math.min(maximum, Math.max(minimum, number));
}

function safeColor(value) {
  return /^#[0-9a-f]{6}$/i.test(String(value)) ? value : "#8b5cf6";
}

function optionList(values, selected, includeBlank = false, blankLabel = "전체") {
  const entries = Object.entries(values);
  const blank = includeBlank ? `<option value="">${escapeHTML(blankLabel)}</option>` : "";
  return blank + entries.map(([value, label]) => (
    `<option value="${escapeHTML(value)}"${value === selected ? " selected" : ""}>${escapeHTML(label)}</option>`
  )).join("");
}

function priorityOptions(selected) {
  return ["P0", "P1", "P2", "P3"].map((value) => (
    `<option value="${value}"${value === selected ? " selected" : ""}>${value}</option>`
  )).join("");
}

function formatDate(value, fallback = "미정") {
  if (!value) return fallback;
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("ko-KR", { month: "short", day: "numeric" }).format(date);
}

function formatDateTime(value, fallback = "미정") {
  if (!value) return fallback;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("ko-KR", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatFullDateTime(value, fallback = "미정") {
  if (!value) return fallback;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function toDateTimeInput(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function refsFromText(value) {
  return String(value ?? "")
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);
}

function projectById(projectId) {
  return trackerState?.projects.find((project) => project.id === projectId) ?? null;
}

function laneById(laneId) {
  return trackerState?.lanes.find((lane) => lane.id === laneId) ?? null;
}

function showToast(message, isError = false) {
  const toast = $("#toast");
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.toggle("is-error", isError);
  toast.classList.add("is-visible");
  toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 3400);
}

async function fetchState() {
  const response = await fetch("/api/state", { cache: "no-store" });
  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error((payload.details || ["상태를 불러오지 못했습니다."]).join(" · "));
  }
  trackerState = payload;
  renderAll();
}

async function postAction(payload, successMessage = "저장했습니다.") {
  const response = await fetch("/api/action", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const result = await response.json();
  if (!response.ok || !result.ok) {
    throw new Error((result.details || ["요청이 거절되었습니다."]).join(" · "));
  }
  trackerState = result.state;
  renderAll();
  showToast(successMessage);
  return result.state;
}

function emptyState(title, message) {
  return `<div class="empty-state"><div><strong>${escapeHTML(title)}</strong><p>${escapeHTML(message)}</p></div></div>`;
}

function renderMetrics() {
  const summary = trackerState.derived.summary;
  const metrics = [
    ["ACTIVE PROJECTS", summary.active_projects, "개", "현재 취소·완료 제외", "#9c7cff"],
    ["VERIFIED PROGRESS", summary.verified_progress == null ? "—" : summary.verified_progress, summary.verified_progress == null ? "" : "%", `${summary.measurable_projects}개 기준선 확정`, "#4ed09a"],
    ["NEEDS ATTENTION", summary.attention_projects, "개", "막힘·일정 지연", "#ffbc5b"],
    ["FOUNDER DECISIONS", summary.pending_decisions, "건", "현재 결정 대기", "#ec4899"],
    ["BASELINE PENDING", summary.baseline_pending, "개", "완료율 계산 전", "#60a5fa"],
  ];
  $("#metric-strip").innerHTML = metrics.map(([label, value, unit, foot, color]) => `
    <article class="metric-card" style="--metric-color:${safeColor(color)}">
      <div class="metric-card-head"><span>${escapeHTML(label)}</span><i></i></div>
      <div class="metric-value"><strong>${escapeHTML(value)}</strong><span>${escapeHTML(unit)}</span></div>
      <div class="metric-foot">${escapeHTML(foot)}</div>
    </article>
  `).join("");
}

function renderFocus() {
  const items = trackerState.derived.focus_items.slice(0, 6);
  $("#focus-list").innerHTML = items.length ? items.map((item, index) => `
    <article class="focus-item" data-project-id="${escapeHTML(item.project_id)}" tabindex="0">
      <span class="focus-rank">${String(index + 1).padStart(2, "0")}</span>
      <div class="focus-content">
        <strong>${escapeHTML(item.title)}</strong>
        <p>${escapeHTML(item.next_action)}</p>
      </div>
      <i class="focus-health health-${escapeHTML(item.health)}" title="${escapeHTML(HEALTH_STATUSES[item.health] || item.health)}"></i>
    </article>
  `).join("") : emptyState("지금 볼 항목이 없습니다", "모든 프로젝트에 다음 행동을 등록해 두면 여기에 정렬됩니다.");
}

function renderLaneSummary() {
  const active = trackerState.projects.filter((project) => !["completed", "canceled"].includes(project.status));
  const total = Math.max(1, active.length);
  $("#lane-summary").innerHTML = trackerState.lanes.map((lane) => {
    const count = active.filter((project) => project.lane_id === lane.id).length;
    const width = (count / total) * 100;
    return `
      <div class="lane-row" style="--lane-color:${safeColor(lane.color)}">
        <span class="lane-label"><i></i>${escapeHTML(lane.short_name || lane.name)}</span>
        <span class="lane-track"><span style="width:${clamp(width)}%"></span></span>
        <strong>${count}</strong>
      </div>
    `;
  }).join("");
}

function projectCard(project) {
  const color = safeColor(project.lane?.color);
  const progress = project.progress;
  const percentage = progress.available ? clamp(progress.percent) : 0;
  const verifiedMilestones = project.milestones.filter((milestone) => milestone.derived.verified_complete).length;
  return `
    <article class="project-card" data-project-id="${escapeHTML(project.id)}" tabindex="0" style="--lane-color:${color}">
      <div class="project-card-top">
        <span class="lane-badge">${escapeHTML(project.lane?.short_name || project.lane_id)}</span>
        <div class="project-card-top-right">
          <span class="priority-badge">${escapeHTML(project.priority)}</span>
          <span class="health-badge health-${escapeHTML(project.observed_health)}">${escapeHTML(HEALTH_STATUSES[project.observed_health] || project.observed_health)}</span>
        </div>
      </div>
      <h3 class="project-title">${escapeHTML(project.title)}</h3>
      <p class="project-objective">${escapeHTML(project.objective || "목표 미등록")}</p>
      <div class="project-progress-row">
        <div class="progress-ring${progress.available ? "" : " is-pending"}" style="--progress:${percentage}">
          <strong>${progress.available ? `${percentage}%` : "기준선\n대기"}</strong>
        </div>
        <div class="project-progress-copy">
          <strong>${progress.available ? "검증 완료율" : progress.reason}</strong>
          <div class="mini-track"><span style="width:${percentage}%"></span></div>
          <small>${verifiedMilestones}/${project.milestones.length} milestone verified</small>
        </div>
      </div>
      <footer class="project-card-footer">
        <div class="project-next"><span>NEXT ACTION</span><strong>${escapeHTML(project.next_action || "미등록")}</strong></div>
        <div class="project-date"><span>TARGET</span><strong>${escapeHTML(formatDate(project.target_date))}</strong></div>
      </footer>
    </article>
  `;
}

function renderProjects() {
  $("#overview-projects").innerHTML = trackerState.projects.slice(0, 4).map(projectCard).join("");

  const query = projectSearch.trim().toLocaleLowerCase("ko");
  const filtered = trackerState.projects.filter((project) => {
    const laneMatches = laneFilter === "all" || project.lane_id === laneFilter;
    const textMatches = !query || `${project.title} ${project.objective} ${project.next_action}`.toLocaleLowerCase("ko").includes(query);
    return laneMatches && textMatches;
  });
  $("#all-projects").innerHTML = filtered.length
    ? filtered.map(projectCard).join("")
    : emptyState("조건에 맞는 프로젝트가 없습니다", "Lane 필터나 검색어를 바꿔 보세요.");

  $("#lane-filter").innerHTML = [
    `<button class="${laneFilter === "all" ? "is-active" : ""}" data-lane-filter="all" type="button">전체</button>`,
    ...trackerState.lanes.map((lane) => `<button class="${laneFilter === lane.id ? "is-active" : ""}" data-lane-filter="${escapeHTML(lane.id)}" type="button">${escapeHTML(lane.short_name || lane.name)}</button>`),
  ].join("");
}

function renderTimeline() {
  $("#timeline-list").innerHTML = trackerState.projects.map((project) => {
    const schedule = project.schedule;
    const progress = project.progress.available ? clamp(project.progress.percent) : 0;
    const timing = schedule.dates_complete
      ? `<div class="timeline-track"><span class="timeline-time" style="width:${clamp(schedule.elapsed_percent)}%"></span><span class="timeline-progress" style="width:${progress}%"></span></div>`
      : `<div class="timeline-no-date">기간 미정 — 시작일과 목표일을 입력하세요</div>`;
    return `
      <article class="timeline-item" data-project-id="${escapeHTML(project.id)}" style="--lane-color:${safeColor(project.lane?.color)}">
        <div class="timeline-project"><strong>${escapeHTML(project.title)}</strong><span>${escapeHTML(project.lane?.short_name || project.lane_id)} · ${escapeHTML(PROJECT_STATUSES[project.status] || project.status)}</span></div>
        ${timing}
        <div class="timeline-dates"><span>${escapeHTML(formatDate(project.start_date))}</span><span>→ ${escapeHTML(formatDate(project.target_date))}</span></div>
      </article>
    `;
  }).join("");

  const entries = [];
  trackerState.projects.forEach((project) => {
    if (project.target_date) entries.push({ date: project.target_date, type: "프로젝트 목표", title: project.title, projectId: project.id, health: project.observed_health });
    if (project.next_review_at) entries.push({ date: project.next_review_at.slice(0, 10), datetime: project.next_review_at, type: "정기 점검", title: project.title, projectId: project.id, health: project.schedule.review_overdue ? "attention" : project.observed_health });
    project.milestones.forEach((milestone) => {
      if (milestone.target_date && !["completed", "canceled"].includes(milestone.status)) {
        entries.push({ date: milestone.target_date, type: "마일스톤", title: `${project.title} · ${milestone.title}`, projectId: project.id, health: milestone.derived.overdue ? "attention" : project.observed_health });
      }
    });
  });
  entries.sort((a, b) => a.date.localeCompare(b.date));
  $("#schedule-table").innerHTML = entries.length ? `
    <thead><tr><th>날짜</th><th>구분</th><th>항목</th><th>신호</th></tr></thead>
    <tbody>${entries.slice(0, 20).map((entry) => `
      <tr data-project-id="${escapeHTML(entry.projectId)}">
        <td>${escapeHTML(entry.datetime ? formatDateTime(entry.datetime) : formatDate(entry.date))}</td>
        <td>${escapeHTML(entry.type)}</td>
        <td>${escapeHTML(entry.title)}</td>
        <td><span class="health-badge health-${escapeHTML(entry.health)}">${escapeHTML(HEALTH_STATUSES[entry.health] || entry.health)}</span></td>
      </tr>
    `).join("")}</tbody>
  ` : `<tbody><tr><td>${emptyState("등록된 날짜가 없습니다", "프로젝트나 마일스톤 목표일을 입력하면 일정에 표시됩니다.")}</td></tr></tbody>`;
}

function renderDecisions() {
  const decisions = [...trackerState.decisions].sort((a, b) => Number(a.status !== "pending") - Number(b.status !== "pending"));
  $("#decision-list").innerHTML = decisions.length ? decisions.map((decision) => {
    const project = decision.project_id ? projectById(decision.project_id) : null;
    return `
      <article class="decision-card">
        <div class="decision-symbol">◇</div>
        <div class="decision-copy">
          <strong>${escapeHTML(decision.title)}</strong>
          <p>${escapeHTML(decision.impact || "영향 미등록")}</p>
          <div class="decision-meta">
            <span>${escapeHTML(project?.title || "전사")}</span>
            <span>Owner ${escapeHTML(decision.owner)}</span>
            <span>필요 ${escapeHTML(formatDate(decision.needed_by))}</span>
            ${decision.derived.overdue ? "<span>기한 경과</span>" : ""}
          </div>
        </div>
        <div class="decision-controls">
          <select class="inline-select" data-decision-status="${escapeHTML(decision.id)}" aria-label="결정 상태">${optionList(DECISION_STATUSES, decision.status)}</select>
        </div>
      </article>
    `;
  }).join("") : emptyState("결정 항목이 없습니다", "선택이나 승인으로 진행이 갈리는 지점을 별도로 기록하세요.");
}

function renderExecutions() {
  $("#execution-list").innerHTML = trackerState.executions.length ? trackerState.executions.map((execution) => {
    const project = projectById(execution.project_id);
    return `
      <article class="execution-card">
        <div class="execution-symbol">◎</div>
        <div class="execution-copy">
          <strong>${escapeHTML(execution.title)}</strong>
          <p>${escapeHTML(execution.expected_output || "기대 산출물 미등록")}</p>
          <div class="execution-meta">
            <span>${escapeHTML(project?.title || execution.project_id)}</span>
            <span>${escapeHTML(execution.agent)}</span>
            <span>${escapeHTML(execution.thread_ref || "task ref 없음")}</span>
            <span>업데이트 ${escapeHTML(formatDateTime(execution.updated_at))}</span>
            <span>진행률 반영 안 함</span>
          </div>
        </div>
        <div class="execution-controls">
          <select class="inline-select" data-execution-status="${escapeHTML(execution.id)}" aria-label="AI 작업 상태">${optionList(EXECUTION_STATUSES, execution.status)}</select>
          <select class="inline-select" data-execution-result="${escapeHTML(execution.id)}" aria-label="결과 검증 상태">${optionList(RESULT_STATES, execution.result_state)}</select>
        </div>
      </article>
    `;
  }).join("") : emptyState("기록된 AI 작업이 없습니다", "필요할 때 실행·반환·검토를 프로젝트와 연결할 수 있습니다.");
}

function renderWorkers() {
  const operations = trackerState.derived.operations;
  const run = operations.selected_mv_run;
  const runSelect = $("#worker-run-select");
  runSelect.innerHTML = run
    ? `<option value="${escapeHTML(run.run_id)}">${escapeHTML(run.run_id)}</option>`
    : '<option value="">현재 run 없음</option>';
  runSelect.disabled = true;

  if (!run) {
    $("#worker-run-banner").innerHTML = emptyState("현재 MV run을 찾지 못했습니다", "schema-valid active/hold run-manifest를 확인하세요.");
    $("#worker-summary").innerHTML = "";
    $("#worker-projection-note").textContent = "worker projection 없음";
    $("#worker-list").innerHTML = "";
    return;
  }

  const projection = run.worker_projection;
  const counts = projection?.counts || {};
  $("#worker-run-banner").innerHTML = `
    <div class="worker-run-main">
      <span class="section-label">CURRENT MV RUN · ${escapeHTML(run.status).toUpperCase()}</span>
      <h2>${escapeHTML(run.run_id)}</h2>
      <p>${escapeHTML(run.root)}</p>
    </div>
    <div class="worker-run-meta">
      <div><span>CONTENT</span><strong>${escapeHTML(run.content_id)}</strong></div>
      <div><span>CREATED</span><strong>${escapeHTML(formatDateTime(run.created_at))}</strong></div>
      <div><span>DEADLINE</span><strong class="deadline-${escapeHTML(run.deadline.state)}">${escapeHTML(run.deadline.day_label)} · ${escapeHTML(formatDateTime(run.deadline.at))}</strong></div>
    </div>`;

  const summaryItems = [
    ["CURRENT HEADS", counts.registered_heads || 0, "lineage별 최신 attempt", "#a985ff"],
    ["LAUNCHED", counts.launched || 0, "실행 등록 · 생존 미확인 가능", "#60a5fa"],
    ["REVIEW QUEUE", (counts.returned || 0) + (counts.reviewed || 0), "반환/검토 이후 승격 전", "#ffbc5b"],
    ["PROMOTED", counts.promoted || 0, "Overall 승격 기록", "#4ed09a"],
    ["HOLD", counts.hold || 0, "판단 또는 보완 필요", "#ff6f7d"],
    ["HISTORY", counts.history_attempts || 0, "현재 head 아래 접힘", "#8f93a2"],
  ];
  $("#worker-summary").innerHTML = summaryItems.map(([label, value, note, color]) => `
    <article class="worker-summary-card" style="--worker-accent:${safeColor(color)}">
      <span>${escapeHTML(label)}</span><strong>${escapeHTML(value)}</strong><small>${escapeHTML(note)}</small>
    </article>
  `).join("");

  $("#worker-projection-note").innerHTML = `
    <strong>${projection?.projection_complete ? "DDI CURRENT VIEW" : "DIRECT PROJECTION · INCOMPLETE"}</strong>
    <span>${escapeHTML(projection?.note || "worker source 없음")} · 파일 수나 launched 상태는 완료율 또는 실제 생존 증거가 아닙니다.</span>`;

  const query = workerSearch.trim().toLocaleLowerCase("ko");
  const workers = (projection?.workers || []).filter((worker) => {
    const stateMatches = workerStateFilter === "all" || worker.execution_state === workerStateFilter;
    const searchable = `${worker.dispatch_id} ${worker.lineage_id} ${worker.role} ${worker.stage_id} ${(worker.section_ids || []).join(" ")} ${worker.recipient_owner}`.toLocaleLowerCase("ko");
    return stateMatches && (!query || searchable.includes(query));
  });
  $("#worker-list").innerHTML = workers.length ? workers.map((worker) => {
    const sections = worker.section_ids?.length ? worker.section_ids.join(", ") : "전체/미지정";
    const outputText = worker.outputs?.declared
      ? `${worker.outputs.existing}/${worker.outputs.declared} declared output path 존재`
      : "declared output 없음";
    return `<article class="worker-card worker-state-${escapeHTML(worker.execution_state)}">
      <div class="worker-card-state"><i></i><span>${escapeHTML(WORKER_STATES[worker.execution_state] || worker.execution_state)}</span></div>
      <div class="worker-card-copy">
        <div class="worker-card-heading">
          <strong>${escapeHTML(worker.dispatch_id)}</strong>
          <span>${escapeHTML(worker.role)}</span>
        </div>
        <div class="worker-scope">
          <span><small>STAGE</small>${escapeHTML(worker.stage_id)}</span>
          <span><small>SECTION</small>${escapeHTML(sections)}</span>
          <span><small>RECIPIENT</small>${escapeHTML(worker.recipient_owner)}</span>
          <span><small>ATTEMPT</small>${escapeHTML(worker.attempt_number)}</span>
        </div>
        <div class="worker-card-foot">
          <span>review ${escapeHTML(worker.review_state)}</span>
          <span>promotion ${escapeHTML(worker.promotion_state)}</span>
          <span>${escapeHTML(outputText)}</span>
          <span>last ${escapeHTML(formatDateTime(worker.last_event_at))}</span>
        </div>
        ${worker.attention_reason ? `<p class="worker-attention">${escapeHTML(worker.attention_reason)}</p>` : ""}
      </div>
    </article>`;
  }).join("") : emptyState("조건에 맞는 작업자가 없습니다", "상태 필터나 검색어를 바꿔 보세요.");
}

function renderSources() {
  const repos = trackerState.derived.git_repositories;
  $("#repo-signals").innerHTML = repos.map((repo) => {
    const stateClass = !repo.available ? "is-error" : repo.dirty_available === false ? "is-dirty" : repo.dirty ? "is-dirty" : "";
    const stateLabel = !repo.available ? "확인 실패" : repo.dirty_available === false ? "tracked 상태 미확인" : repo.dirty ? `tracked 변경 ${repo.dirty_count}` : "tracked clean";
    return `
      <article class="repo-card">
        <div class="repo-card-head"><h3>${escapeHTML(repo.label)}</h3><span class="repo-state ${stateClass}"><i></i>${escapeHTML(stateLabel)}</span></div>
        <div class="repo-details">
          <div class="repo-detail"><span>BRANCH</span><strong>${escapeHTML(repo.branch || "—")}</strong></div>
          <div class="repo-detail"><span>LAST COMMIT</span><strong>${escapeHTML(repo.last_commit_sha ? repo.last_commit_sha.slice(0, 8) : "—")}</strong></div>
          <div class="repo-detail"><span>AT</span><strong>${escapeHTML(formatDateTime(repo.last_commit_at, "—"))}</strong></div>
        </div>
        ${repo.error || repo.dirty_probe_note ? `<p class="repo-detail"><span>PROBE NOTE</span><strong>${escapeHTML(repo.error || repo.dirty_probe_note)}</strong></p>` : ""}
      </article>
    `;
  }).join("");

  const sources = trackerState.derived.source_catalog;
  $("#source-table").innerHTML = `
    <thead><tr><th>경로</th><th>상태</th><th>종류</th><th>수정</th><th>연결</th></tr></thead>
    <tbody>${sources.map((source) => `
      <tr>
        <td class="source-path">${escapeHTML(source.path)}</td>
        <td><span class="source-status${source.exists ? "" : " is-missing"}"><i></i>${source.exists ? "존재" : "없음"}</span></td>
        <td>${escapeHTML(source.kind || "—")}</td>
        <td>${escapeHTML(formatDateTime(source.modified_at, "—"))}</td>
        <td>${escapeHTML(source.used_by.join(", "))}</td>
      </tr>
    `).join("")}</tbody>
  `;

  const method = trackerState.derived.methodology;
  const cards = [
    ["완료율", method.progress],
    ["AI 실행", method.ai_execution],
    ["원본 경계", method.source_boundary],
  ];
  $("#methodology-list").innerHTML = cards.map(([title, body]) => `<article class="method-card"><strong>${escapeHTML(title)}</strong><p>${escapeHTML(body)}</p></article>`).join("");
}

function populateProjectSelect(select, includeBlank = false) {
  select.innerHTML = `${includeBlank ? '<option value="">전사 / 연결 안 함</option>' : ""}${trackerState.projects.map((project) => `<option value="${escapeHTML(project.id)}">${escapeHTML(project.title)}</option>`).join("")}`;
}

function renderAll() {
  if (!trackerState) return;
  renderMetrics();
  renderFocus();
  renderLaneSummary();
  renderProjects();
  renderTimeline();
  renderDecisions();
  renderExecutions();
  renderWorkers();
  renderSources();

  $("#decision-count").textContent = trackerState.derived.summary.pending_decisions;
  $("#execution-count").textContent = trackerState.derived.summary.active_executions;
  $("#worker-count").textContent = trackerState.derived.operations.summary.worker_heads;
  $("#worker-count").classList.toggle("is-visible", trackerState.derived.operations.summary.worker_heads > 0);
  $("#data-revision").textContent = `DATA REV ${trackerState.meta.revision}`;
  $("#generated-at").textContent = formatDateTime(trackerState.derived.generated_at);

  populateProjectSelect($("#decision-form [name=project_id]"), true);
  populateProjectSelect($("#execution-form [name=project_id]"));

  const templateSelect = $("#create-project-form [name=template_id]");
  templateSelect.innerHTML = trackerState.templates.map((template) => {
    const lane = laneById(template.lane_id);
    return `<option value="${escapeHTML(template.id)}">${escapeHTML(lane?.name || template.id)}</option>`;
  }).join("");
  $("#create-project-form [name=priority]").innerHTML = priorityOptions("P2");
  $("#execution-form [name=status]").innerHTML = optionList(EXECUTION_STATUSES, "queued");
}

function switchView(view) {
  if (!VIEW_LABELS[view]) return;
  activeView = view;
  $$(".nav-item").forEach((item) => item.classList.toggle("is-active", item.dataset.view === view));
  $$("[data-view-panel]").forEach((panel) => panel.classList.toggle("is-active", panel.dataset.viewPanel === view));
  $("#view-eyebrow").textContent = VIEW_LABELS[view][0];
  $("#view-title").textContent = VIEW_LABELS[view][1];
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function milestoneEditor(project) {
  const locked = project.baseline.state === "locked";
  return project.milestones.map((milestone) => `
    <article class="milestone-row" data-milestone-id="${escapeHTML(milestone.id)}">
      <div class="milestone-row-head">
        <label class="compact-field"><span>마일스톤</span><input data-field="title" value="${escapeHTML(milestone.title)}"${locked ? " disabled" : ""}></label>
        <label class="compact-field"><span>가중치</span><input data-field="weight" type="number" min="0.1" step="0.1" value="${escapeHTML(milestone.weight)}"${locked ? " disabled" : ""}></label>
        <label class="compact-field"><span>상태</span><select data-field="status">${optionList(MILESTONE_STATUSES, milestone.status)}</select></label>
        <label class="compact-field"><span>Gate</span><select data-field="gate_status">${optionList(GATE_STATUSES, milestone.gate_status)}</select></label>
      </div>
      <div class="milestone-row-details">
        <label class="compact-field"><span>시작일</span><input data-field="start_date" type="date" value="${escapeHTML(milestone.start_date || "")}"></label>
        <label class="compact-field"><span>목표일</span><input data-field="target_date" type="date" value="${escapeHTML(milestone.target_date || "")}"></label>
        <label class="compact-field"><span>Owner</span><input data-field="owner" value="${escapeHTML(milestone.owner || "")}"></label>
        <label class="compact-field evidence-field"><span>근거 경로 · 한 줄에 하나</span><textarea data-field="evidence_refs" rows="2">${escapeHTML((milestone.evidence_refs || []).join("\n"))}</textarea></label>
        <label class="compact-field"><span>증거 필수</span><select data-field="evidence_required"${locked ? " disabled" : ""}><option value="true"${milestone.evidence_required ? " selected" : ""}>필수</option><option value="false"${milestone.evidence_required ? "" : " selected"}>선택</option></select></label>
        <label class="compact-field" style="grid-column:span 2"><span>메모</span><textarea data-field="note" rows="2">${escapeHTML(milestone.note || "")}</textarea></label>
      </div>
      <div class="milestone-readout">
        <span class="evidence-badge">${escapeHTML(milestone.derived.evidence_state)}</span>
        <span class="gate-badge">${escapeHTML(GATE_STATUSES[milestone.gate_status])}</span>
        <span>${milestone.derived.verified_complete ? "완료율 반영" : "완료율 미반영"}</span>
        ${milestone.derived.warnings.length ? `<span>${escapeHTML(milestone.derived.warnings.join(" · "))}</span>` : ""}
      </div>
    </article>
  `).join("");
}

function blockerEditor(project) {
  return project.blockers.length ? project.blockers.map((blocker) => `
    <article class="blocker-row${blocker.status === "resolved" ? " is-resolved" : ""}">
      <div><strong>${escapeHTML(blocker.title)}</strong><span>${escapeHTML(blocker.owner)} · ${blocker.status === "resolved" ? `해결 ${formatDateTime(blocker.resolved_at)}` : `열림 ${formatDateTime(blocker.opened_at)}`}</span></div>
      ${blocker.status === "open" ? `<button class="button button-small button-quiet" data-resolve-blocker="${escapeHTML(blocker.id)}" type="button">해결</button>` : ""}
    </article>
  `).join("") : emptyState("열린 Blocker가 없습니다", "진행을 실제로 막는 조건만 기록합니다.");
}

function openProject(projectId) {
  const project = projectById(projectId);
  if (!project) return;
  activeProjectId = projectId;
  const form = $("#project-form");
  $("#project-dialog-lane").textContent = project.lane?.name || project.lane_id;
  $("#project-dialog-title").textContent = project.title;
  form.elements.title.value = project.title;
  form.elements.objective.value = project.objective || "";
  form.elements.status.innerHTML = optionList(PROJECT_STATUSES, project.status);
  form.elements.declared_health.innerHTML = optionList(HEALTH_STATUSES, project.declared_health);
  form.elements.priority.innerHTML = priorityOptions(project.priority);
  form.elements.owner.value = project.owner || "";
  form.elements.start_date.value = project.start_date || "";
  form.elements.target_date.value = project.target_date || "";
  form.elements.next_review_at.value = toDateTimeInput(project.next_review_at);
  form.elements.review_cadence_days.value = project.review_cadence_days;
  form.elements.next_action.value = project.next_action || "";
  form.elements.source_refs.value = (project.source_refs || []).join("\n");

  const locked = project.baseline.state === "locked";
  $("#project-baseline-card").innerHTML = `
    <div class="baseline-card${locked ? " is-locked" : ""}">
      <div><strong>${locked ? `기준선 잠김 · REV ${project.baseline.revision}` : "기준선 초안"}</strong><p>${locked ? `Founder 확정 ${formatFullDateTime(project.baseline.locked_at)} · 범위와 가중치는 보호됩니다.` : "가중치 합계 100과 완료 증거 규칙을 확인한 뒤 Founder가 잠급니다."}</p></div>
      ${locked ? '<span class="status-badge">LOCKED</span>' : '<button class="button button-primary button-small" id="lock-baseline-button" type="button">기준선 잠금</button>'}
    </div>
  `;
  $("#add-milestone-button").disabled = locked;
  $("#add-milestone-button").title = locked ? "잠긴 기준선에는 마일스톤을 추가할 수 없습니다." : "";
  $("#milestone-editor").innerHTML = milestoneEditor(project);
  $("#blocker-editor").innerHTML = blockerEditor(project);
  $("#project-save-status").textContent = locked ? "scope·weight 보호 중" : "기준선 초안";
  if (!$("#project-dialog").open) $("#project-dialog").showModal();
}

function collectMilestones() {
  return $$("#milestone-editor .milestone-row").map((row) => {
    const value = (field) => $(`[data-field="${field}"]`, row)?.value ?? "";
    return {
      id: row.dataset.milestoneId,
      title: value("title").trim(),
      weight: Number(value("weight")),
      status: value("status"),
      gate_status: value("gate_status"),
      evidence_required: value("evidence_required") === "true",
      evidence_refs: refsFromText(value("evidence_refs")),
      start_date: value("start_date") || null,
      target_date: value("target_date") || null,
      owner: value("owner").trim(),
      note: value("note").trim(),
    };
  });
}

async function saveProject() {
  const project = projectById(activeProjectId);
  if (!project) return;
  const form = $("#project-form");
  const nextReview = form.elements.next_review_at.value;
  const patch = {
    title: form.elements.title.value.trim(),
    objective: form.elements.objective.value.trim(),
    status: form.elements.status.value,
    declared_health: form.elements.declared_health.value,
    priority: form.elements.priority.value,
    owner: form.elements.owner.value.trim(),
    start_date: form.elements.start_date.value || null,
    target_date: form.elements.target_date.value || null,
    next_review_at: nextReview ? new Date(nextReview).toISOString() : null,
    review_cadence_days: Number(form.elements.review_cadence_days.value),
    next_action: form.elements.next_action.value.trim(),
    source_refs: refsFromText(form.elements.source_refs.value),
    milestones: collectMilestones(),
  };
  if (!patch.title) {
    showToast("프로젝트명을 입력하세요.", true);
    return;
  }
  const totalWeight = patch.milestones.reduce((sum, milestone) => sum + milestone.weight, 0);
  if (project.baseline.state !== "locked" && Math.abs(totalWeight - 100) > 0.000001) {
    $("#project-save-status").textContent = `현재 가중치 ${totalWeight} · 잠금 전 100 필요`;
  }
  try {
    await postAction({ action: "update_project", project_id: project.id, patch }, "프로젝트를 저장했습니다.");
    $("#project-dialog").close();
  } catch (error) {
    showToast(error.message, true);
  }
}

function confirmAction(title, message, callback) {
  $("#confirm-title").textContent = title;
  $("#confirm-message").textContent = message;
  pendingConfirmation = callback;
  $("#confirm-dialog").showModal();
}

function openCreateProject() {
  const form = $("#create-project-form");
  form.reset();
  form.elements.owner.value = "Founder";
  form.elements.next_action.value = "기준선과 첫 마일스톤 상태 확정";
  form.elements.priority.innerHTML = priorityOptions("P2");
  $("#create-project-dialog").showModal();
}

async function createProject() {
  const form = $("#create-project-form");
  if (!form.reportValidity()) return;
  try {
    await postAction({
      action: "create_project",
      template_id: form.elements.template_id.value,
      title: form.elements.title.value.trim(),
      objective: form.elements.objective.value.trim(),
      owner: form.elements.owner.value.trim(),
      priority: form.elements.priority.value,
      start_date: form.elements.start_date.value || null,
      target_date: form.elements.target_date.value || null,
      next_action: form.elements.next_action.value.trim(),
    }, "프로젝트를 추가했습니다.");
    $("#create-project-dialog").close();
    switchView("projects");
  } catch (error) {
    showToast(error.message, true);
  }
}

async function addDecision() {
  const form = $("#decision-form");
  if (!form.reportValidity()) return;
  try {
    await postAction({
      action: "add_decision",
      title: form.elements.title.value.trim(),
      project_id: form.elements.project_id.value || null,
      needed_by: form.elements.needed_by.value || null,
      owner: form.elements.owner.value.trim(),
      impact: form.elements.impact.value.trim(),
      source_refs: refsFromText(form.elements.source_refs.value),
    }, "결정 항목을 추가했습니다.");
    $("#decision-dialog").close();
    form.reset();
  } catch (error) {
    showToast(error.message, true);
  }
}

async function addExecution() {
  const form = $("#execution-form");
  if (!form.reportValidity()) return;
  try {
    await postAction({
      action: "add_execution",
      title: form.elements.title.value.trim(),
      project_id: form.elements.project_id.value,
      agent: form.elements.agent.value.trim(),
      status: form.elements.status.value,
      thread_ref: form.elements.thread_ref.value.trim(),
      expected_output: form.elements.expected_output.value.trim(),
      next_action: form.elements.next_action.value.trim(),
    }, "AI 작업을 추가했습니다.");
    $("#execution-dialog").close();
    form.reset();
  } catch (error) {
    showToast(error.message, true);
  }
}

document.addEventListener("click", async (event) => {
  const target = event.target.closest("button, [data-project-id], tr[data-project-id]");
  if (!target) return;

  if (target.matches(".nav-item")) switchView(target.dataset.view);
  if (target.dataset.goView) switchView(target.dataset.goView);
  if (target.dataset.projectId) openProject(target.dataset.projectId);
  if (target.id === "refresh-button") {
    try { await fetchState(); showToast("원본 신호를 다시 확인했습니다."); } catch (error) { showToast(error.message, true); }
  }
  if (target.id === "add-project-button") openCreateProject();
  if (target.id === "create-project-submit") await createProject();
  if (target.id === "add-decision-button") {
    const form = $("#decision-form");
    form.reset();
    form.elements.owner.value = "Founder";
    populateProjectSelect(form.elements.project_id, true);
    $("#decision-dialog").showModal();
  }
  if (target.id === "decision-submit") await addDecision();
  if (target.id === "add-execution-button") {
    const form = $("#execution-form");
    form.reset();
    form.elements.agent.value = "Codex";
    form.elements.status.innerHTML = optionList(EXECUTION_STATUSES, "queued");
    populateProjectSelect(form.elements.project_id);
    $("#execution-dialog").showModal();
  }
  if (target.id === "execution-submit") await addExecution();
  if (target.id === "save-project-button") await saveProject();

  if (target.id === "lock-baseline-button") {
    const project = projectById(activeProjectId);
    const currentWeight = collectMilestones().reduce((sum, milestone) => sum + milestone.weight, 0);
    if (Math.abs(currentWeight - 100) > 0.000001) {
      showToast(`가중치 합계가 ${currentWeight}입니다. 100으로 맞춘 뒤 먼저 저장하세요.`, true);
    } else {
      confirmAction(
        "기준선 잠금",
        "현재 마일스톤 범위와 가중치를 Founder 기준선으로 잠급니다. 잠긴 뒤 범위·가중치는 이 버전에서 바꿀 수 없습니다.",
        async () => {
          await postAction({ action: "lock_baseline", project_id: project.id, locked_by: "Founder" }, "Founder 기준선을 잠갔습니다.");
          $("#confirm-dialog").close();
          openProject(project.id);
        },
      );
    }
  }

  if (target.id === "add-milestone-button") {
    const title = window.prompt("추가할 마일스톤 이름");
    if (!title) return;
    const weight = Number(window.prompt("가중치 (잠금 전 전체 합계 100)", "5"));
    if (!Number.isFinite(weight) || weight <= 0) {
      showToast("가중치는 0보다 큰 숫자여야 합니다.", true);
      return;
    }
    try {
      await postAction({ action: "add_milestone", project_id: activeProjectId, title, weight }, "마일스톤을 추가했습니다.");
      openProject(activeProjectId);
    } catch (error) { showToast(error.message, true); }
  }

  if (target.id === "add-blocker-button") {
    const title = window.prompt("진행을 막는 조건을 적어 주세요.");
    if (!title) return;
    try {
      await postAction({ action: "add_blocker", project_id: activeProjectId, title, owner: "Founder" }, "Blocker를 추가했습니다.");
      openProject(activeProjectId);
    } catch (error) { showToast(error.message, true); }
  }

  if (target.dataset.resolveBlocker) {
    try {
      await postAction({ action: "resolve_blocker", project_id: activeProjectId, blocker_id: target.dataset.resolveBlocker }, "Blocker를 해결 처리했습니다.");
      openProject(activeProjectId);
    } catch (error) { showToast(error.message, true); }
  }

  if (target.id === "confirm-accept" && pendingConfirmation) {
    const callback = pendingConfirmation;
    pendingConfirmation = null;
    try { await callback(); } catch (error) { showToast(error.message, true); }
  }
});

document.addEventListener("change", async (event) => {
  const target = event.target;
  if (target.matches("[data-lane-filter]")) return;
  if (target.dataset.decisionStatus) {
    try {
      await postAction({ action: "update_decision", decision_id: target.dataset.decisionStatus, patch: { status: target.value } }, "결정 상태를 바꿨습니다.");
    } catch (error) { showToast(error.message, true); }
  }
  if (target.dataset.executionStatus) {
    try {
      await postAction({ action: "update_execution", execution_id: target.dataset.executionStatus, patch: { status: target.value } }, "AI 작업 상태를 바꿨습니다.");
    } catch (error) { showToast(error.message, true); }
  }
  if (target.dataset.executionResult) {
    try {
      await postAction({ action: "update_execution", execution_id: target.dataset.executionResult, patch: { result_state: target.value } }, "결과 검증 상태를 바꿨습니다.");
    } catch (error) { showToast(error.message, true); }
  }
});

document.addEventListener("keydown", (event) => {
  const target = event.target.closest?.("[data-project-id]");
  if (target && (event.key === "Enter" || event.key === " ")) {
    event.preventDefault();
    openProject(target.dataset.projectId);
  }
});

$("#lane-filter").addEventListener("click", (event) => {
  const button = event.target.closest("[data-lane-filter]");
  if (!button) return;
  laneFilter = button.dataset.laneFilter;
  renderProjects();
});

$("#project-search").addEventListener("input", (event) => {
  projectSearch = event.target.value;
  renderProjects();
});

$("#worker-state-filter").addEventListener("change", (event) => {
  workerStateFilter = event.target.value;
  renderWorkers();
});

$("#worker-search").addEventListener("input", (event) => {
  workerSearch = event.target.value;
  renderWorkers();
});

$("#confirm-dialog").addEventListener("close", () => { pendingConfirmation = null; });

const requestedView = new URLSearchParams(window.location.search).get("view");

fetchState()
  .then(() => { if (requestedView) switchView(requestedView); })
  .catch((error) => showToast(error.message, true))
  .finally(() => $("#loading-screen").classList.add("is-hidden"));
