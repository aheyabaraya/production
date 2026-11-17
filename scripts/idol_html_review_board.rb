#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "yaml"

class ReviewBoardContractError < StandardError; end

class IdolHtmlReviewBoard
  SCHEMA_VERSIONS = %w[idol-html-review-board.v12].freeze
  GENERATOR_ID = "idol_html_review_board.v12"
  # Historical HTML stays readable evidence. Only v12 manifests are accepted
  # for active authoring and every active cycle uses the canonical G namespace.
  READABLE_GENERATOR_IDS = %w[idol_html_review_board.v6 idol_html_review_board.v7 idol_html_review_board.v8 idol_html_review_board.v9 idol_html_review_board.v10 idol_html_review_board.v12].freeze
  VISUAL_PROFILE_ID = "idol-dark-core-readable-v2"
  FONT_PROFILE_ID = "pretendard-inter-system-v1"
  SHELL_ROOT = "skills/idol-front-planning-director/references/founder-visual-review-board"
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp .gif .avif].freeze
  VIDEO_EXTENSIONS = %w[.mp4 .mov .webm .m4v].freeze
  SHA_RE = /\A[a-f0-9]{64}\z/
  ID_RE = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
  SECTION_ID_RE = /\AS\d{2,}[A-Z]?\z/
  REFERENCE_ROLES = %w[primary_reference supporting_reference context_reference].freeze
  CONTINUITY_PROFILE = "founder-workbench-continuity-v1"
  LANE_ROLES = %w[unassigned member_identity governing_main support_job context_alternative generated_output storyboard_output playback_output edit_output diagnostic].freeze
  ASSET_DISPOSITIONS = %w[new active_used candidate held rejected superseded passed_output].freeze
  ASSET_REVIEW_STATES = %w[pending reviewed_pass reviewed_hold reviewed_reject superseded].freeze

  ROOT_KEYS = %w[schema_version run board sources decision_options sections review_assets].freeze
  ROOT_REQUIRED_KEYS = %w[schema_version run board sources decision_options sections].freeze
  RUN_KEYS = %w[run_root content_id].freeze
  BOARD_KEYS = %w[board_id stage_id review_mode status layout_profile legacy_cycle_aliases revision projection_profile projection_revision last_reviewed_revision source_set_digest active_cycle_id storage_scope output_policy density title eyebrow purpose review_question target_summary message_summary whole_film_flow_summary section_flow_summary storyline_alignment_policy output_path review_sequence rollback_pair notices].freeze
  SOURCE_KEYS = %w[source_id path sha256 role].freeze
  DECISION_KEYS = %w[id label tone].freeze
  SECTION_KEYS = %w[cycle_id cycle_kind review_mode section_id scope_mode covered_section_ids stage_id revision_id status open_by_default supersedes_revision_id decision_owner decision_question legal_actions affected_scope blocking_effect decision_epoch dispatch_id returned_output director_review founder_lineage worker_evidence fragment_ownership board_merge g30_readiness label headline summary facts audit_notes cards].freeze
  CARD_KEYS = %w[card_id card_type route_id route_readiness eyebrow title variant direction screen_proof screen_summary storyline_readout review_question decision_question decision_owner legal_actions affected_scope blocking_effect decision_epoch dispatch_id returned_output director_review founder_lineage worker_evidence fragment_ownership board_merge review_phase phase_state decision_scope revision_scope affected_section_ids review_target source_field_refs facts media].freeze
  FACT_KEYS = %w[label value style].freeze
  MEDIA_KEYS = %w[asset_id surface_locator path sha256 alt label note media_type role inspection_action receipt display_lane].freeze
  ASSET_REFERENCE_KEYS = %w[asset_id binding_id].freeze
  REVIEW_ASSET_KEYS = %w[asset_id surface_locator canonical_path sha256 alt label note media_kind original_owner role inspection_action display_lane receipt first_seen_board_revision supersedes_asset_id superseded_by_asset_id bindings].freeze
  REVIEW_ASSET_BINDING_KEYS = %w[binding_id assignment_state target_id target_level source_stage section_id planning_cut_id core_cut_id branch_cut_id declared_order lane_role disposition review_state new_since_last_review latest_binding_revision state_receipt].freeze
  REVIEW_PHASE_KEYS = %w[phase order stage_id gate].freeze
  SOURCE_SET_DIGEST_KEYS = %w[algorithm basis sha256 entry_count].freeze
  ROLLBACK_PAIR_KEYS = %w[last_passed_manifest last_passed_html].freeze
  REVIEW_TARGET_KEYS = %w[target_id parent_target_id level display_number label section_id planning_cut_id core_cut_id branch_cut_id].freeze
  STORYLINE_READOUT_KEYS = %w[alignment_level progression_depth title source_field_ref source_value_sha256 visual_relationship exact_source_projection visual_mismatch_action mismatch_state mismatch_note].freeze
  SURFACE_LOCATOR_KEYS = %w[source_asset_id selected_cell_or_frame_id surface_kind source_timecode].freeze
  RECEIPT_KEYS = %w[receipt_id source_identity disposition function follow_strength preserve discard].freeze
  POINTER_KEYS = %w[source_id pointer join].freeze
  NOTICE_KEYS = %w[tone text].freeze
  CYCLE_KINDS = %w[g00_direction_draft g10_song_lock g20_visual_identity_lock g30_fp_final g30_experiment_disposition g40_core_branch_authorization g50_branch_results video_playback_internal g60_playback_edit g70_release].freeze
  CYCLE_ORDER = CYCLE_KINDS.each_with_index.to_h.freeze
  LEGACY_CYCLE_ALIASES = {
    "discovery" => "g00_direction_draft",
    "direction_synthesis" => "g30_fp_final",
    "fp_final" => "g40_core_branch_authorization"
  }.freeze
  CYCLE_KIND_MODE = {
    "g00_direction_draft" => "g00_direction_draft",
    "g10_song_lock" => "g10_song_lock",
    "g20_visual_identity_lock" => "g20_visual_identity_lock",
    "g30_fp_final" => "g30_fp_final",
    "g30_experiment_disposition" => "g30_experiment_disposition",
    "g40_core_branch_authorization" => "g40_core_branch_authorization",
    "g50_branch_results" => "g50_branch_results",
    "video_playback_internal" => "video_playback_internal",
    "g60_playback_edit" => "g60_playback_edit",
    "g70_release" => "g70_release"
  }.freeze
  MODE_LEGAL_ACTIONS = {
    "g00_direction_draft" => %w[attracted reject hold connect_these keep_only search_further direct_comment],
    "g10_song_lock" => %w[pass hold reject],
    "g20_visual_identity_lock" => %w[pass hold reject],
    "g30_fp_final" => %w[select_candidate hold reject direct_comment],
    "g30_experiment_disposition" => %w[reject_archive revise_experiment teaser_only teaser_first_full_mv_hold full_mv_development hold],
    "g40_core_branch_authorization" => %w[pass hold reject],
    "g50_branch_results" => %w[pass hold reject],
    "video_playback_internal" => %w[internal_pass internal_hold material_exception],
    "g60_playback_edit" => %w[pass hold reject],
    "g70_release" => %w[pass hold reject]
  }.freeze
  MODE_BLOCKING_EFFECT = {
    "g00_direction_draft" => "non_gating_signal_only",
    "g10_song_lock" => "advances_or_holds_only_bound_scope",
    "g20_visual_identity_lock" => "advances_or_holds_only_bound_scope",
    "g30_fp_final" => "only_explicitly_named_field_or_card_is_fixed",
    "g30_experiment_disposition" => "routes_derivative_scope_without_discarding_other_derivatives",
    "g40_core_branch_authorization" => "advances_or_holds_only_bound_scope",
    "g50_branch_results" => "advances_or_holds_only_bound_scope",
    "video_playback_internal" => "internal_playback_checkpoint_only",
    "g60_playback_edit" => "advances_or_holds_only_bound_scope",
    "g70_release" => "advances_or_holds_only_bound_scope"
  }.freeze
  OWNER_ROLES = %w[creative_development_director overall_director edit_director].freeze

  attr_reader :manifest, :manifest_path, :repo_root, :output_path, :manifest_sha256

  def initialize(manifest_path, repo_root:)
    @repo_root = Pathname.new(repo_root).expand_path.cleanpath
    @manifest_path = Pathname.new(manifest_path).expand_path.cleanpath
    raise ReviewBoardContractError, "repository root does not exist: #{@repo_root}" unless @repo_root.directory?
    raise ReviewBoardContractError, "repository root is a symlink" if @repo_root.symlink?
    raise ReviewBoardContractError, "manifest does not exist: #{@manifest_path}" unless @manifest_path.file?

    @bound_inputs = {}
    @shell_bytes = {}
    @manifest = load_document(@manifest_path, "manifest")
    @manifest_sha256 = @bound_inputs.fetch(@manifest_path.to_s).fetch(:sha256)
    @source_documents = {}
    @source_rows = {}
    @resolved_media = {}
    @resolved_surfaces = {}
    @asset_bindings = {}
    @review_assets = {}
    @review_asset_bindings = {}
    @review_asset_physical_identities = {}
    @continuity_profile = @manifest.dig("board", "projection_profile") == CONTINUITY_PROFILE
    validate!
  end

  def validate!
    expect_hash(@manifest, "manifest")
    expect_keys(@manifest, ROOT_REQUIRED_KEYS, ROOT_KEYS, "manifest")
    expect_member(@manifest["schema_version"], SCHEMA_VERSIONS, "schema_version")
    @workbench = true
    @hierarchical_workbench = true
    @review_mode = @manifest.dig("board", "review_mode")

    validate_run!
    validate_sources!
    validate_board!
    validate_decisions!
    validate_review_assets! if @continuity_profile
    validate_sections!
    @expected_output = output_snapshot!
    self
  end

  def render_html
    board = @manifest.fetch("board")
    sections = @manifest.fetch("sections")
    density = board.fetch("density", "comfortable")
    source_digest = Digest::SHA256.hexdigest(JSON.generate(@source_rows.values.sort_by { |row| row.fetch("source_id") }))
    manifest_rel = relative_to_repo(@manifest_path)
    title = resolve_text(board.fetch("title"), "board.title")
    eyebrow = board.key?("eyebrow") ? resolve_text(board["eyebrow"], "board.eyebrow") : board.fetch("stage_id")
    purpose = resolve_text(board.fetch("purpose"), "board.purpose")
    review_question = resolve_text(board.fetch("review_question"), "board.review_question")
    target_summary = resolve_text(board.fetch("target_summary"), "board.target_summary")
    message_summary = resolve_text(board.fetch("message_summary"), "board.message_summary")
    whole_film_flow_summary = resolve_text(board.fetch("whole_film_flow_summary"), "board.whole_film_flow_summary")
    section_flow_summary = resolve_text(board.fetch("section_flow_summary"), "board.section_flow_summary")
    board_revision = board.fetch("revision", 1)
    review_mode = board.fetch("review_mode")
    asset_counts = review_asset_counts
    decisions_json = JSON.generate(@manifest.fetch("decision_options")).gsub("</", "<\\/")
    decision_metadata_json = JSON.generate(decision_metadata_map).gsub("</", "<\\/")
    storage_key = if @hierarchical_workbench
      "idol-review-board:#{board.fetch('board_id')}:r#{board_revision}:#{@manifest_sha256}"
    elsif @workbench
      "idol-review-board:#{board.fetch('board_id')}"
    else
      "idol-review-board:#{board.fetch('board_id')}:#{@manifest_sha256}"
    end

    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="idol-generator" content="#{GENERATOR_ID}">
        <meta name="idol-review-board-manifest" content="#{h(manifest_rel)}">
        <meta name="idol-review-board-manifest-sha256" content="#{@manifest_sha256}">
        <meta name="idol-review-board-source-digest" content="#{source_digest}">
        <meta name="idol-review-status" content="#{h(board.fetch('status'))}">
        <meta name="idol-review-board-revision" content="#{board_revision}">
        <meta name="idol-review-board-active-cycle" content="#{h(board.fetch('active_cycle_id'))}">
        <meta name="idol-review-board-projection-profile" content="#{h(board.fetch('projection_profile', 'legacy-v8'))}">
        <meta name="idol-review-board-projection-revision" content="#{board.fetch('projection_revision', board_revision)}">
        <meta name="idol-review-board-asset-counts" content="#{h(JSON.generate(asset_counts))}">
        <meta name="idol-review-mode" content="#{h(review_mode)}">
        <meta name="idol-review-board-visual-profile" content="#{VISUAL_PROFILE_ID}">
        <meta name="idol-review-board-font-profile" content="#{FONT_PROFILE_ID}">
        <meta name="idol-review-board-shell-css-sha256" content="#{shell_asset_sha('board-shell.css')}">
        <meta name="idol-review-board-lightbox-js-sha256" content="#{shell_asset_sha('board-lightbox.js')}">
        <link rel="icon" href="data:,">
        <title>#{h(title)}</title>
        <style>#{stylesheet}</style>
      </head>
      <body class="density-#{h(density)} review-mode-#{h(review_mode)}" data-board-revision="#{board_revision}" data-active-cycle="#{h(board.fetch('active_cycle_id'))}">
        <header class="hero">
          <div class="hero-meta">#{h(eyebrow)} · #{h(review_mode)} · #{h(board.fetch('status'))}</div>
          <h1>#{h(title)}</h1>
          <p class="purpose">#{text_html(purpose)}</p>
          <div class="review-question"><span>REVIEW QUESTION</span>#{text_html(review_question)}</div>
          <section class="creative-spine" aria-label="Locked creative spine">
            <div><span>TARGET</span>#{text_html(target_summary)}</div>
            <div><span>MESSAGE</span>#{text_html(message_summary)}</div>
            <div><span>WHOLE-VIDEO FLOW</span>#{text_html(whole_film_flow_summary)}</div>
            <div><span>SECTION FLOW</span>#{text_html(section_flow_summary)}</div>
          </section>
          #{render_notices(board.fetch("notices", []))}
          <details class="provenance">
            <summary>Sources · hashes · #{@source_rows.length} bound file(s)</summary>
            <div class="provenance-grid">#{render_sources}</div>
          </details>
        </header>
        <nav class="section-nav" aria-label="Section navigation">
          #{sections.map { |section|
              section_id = section["section_id"] || section.fetch("cycle_id")
              cycle_id = @workbench ? section.fetch("cycle_id") : section_id
              nav_label = if @workbench
                "#{review_scope_label(section)} · #{section.fetch('revision_id')} · #{section.fetch('status')}"
              else
                resolve_text(section.fetch("label"), "section.label")
              end
              %(<a href="##{h(cycle_id)}">#{h(nav_label)}</a>)
            }.join}
        </nav>
        #{@workbench ? %(<div class="workbench-tools"><button type="button" id="expandAll">Expand all</button><button type="button" id="collapseAll">Collapse all</button><button type="button" id="showPending" aria-pressed="false">Show pending only</button></div>) : ""}
        #{@continuity_profile ? render_review_asset_register : ""}
        #{render_branch_cut_nav(sections)}
        <main>
          #{sections.each_with_index.map { |section, index| render_section(section, index) }.join("\n")}
        </main>
        <aside class="decision-dock" aria-label="Review decision export">
          <div><strong>Local review decisions</strong><span id="decisionCount">0 / 0 recorded</span></div>
          <div class="decision-actions"><button type="button" id="copyDecisions">Copy JSON</button>#{@workbench ? %(<button type="button" id="downloadDecisions">Save JSON</button>) : ""}</div>
        </aside>
        <footer>
          <p>This HTML is derived review material regenerated from <code>#{h(manifest_rel)}</code>. It is not canonical creative truth, Founder approval, 02B approval, or generation approval.</p>
          <p>manifest SHA-256 <code>#{@manifest_sha256}</code> · source digest <code>#{source_digest}</code></p>
        </footer>
        <div id="lb" role="dialog" aria-modal="true" aria-label="Image enlargement">
          <span class="lb-x" id="lb-x" title="Close">×</span>
          <span class="lb-hint">Click background or press Esc to close</span>
          <img id="lb-img" src="" alt="Enlarged review media">
          <div class="lb-cap" id="lb-cap"></div>
        </div>
        <script>#{lightbox_script}</script>
        <script>
          (() => {
            const options = #{decisions_json};
            const decisionMetadata = #{decision_metadata_json};
            const storageKey = #{JSON.generate(storage_key)};
            const viewStorageKey = #{JSON.generate("idol-review-board-view:#{board.fetch('board_id')}")};
            const state = JSON.parse(localStorage.getItem(storageKey) || '{}');
            const viewState = JSON.parse(localStorage.getItem(viewStorageKey) || '{}');
            const buttons = [...document.querySelectorAll('[data-review-key][data-review-choice]')];
            const notes = [...document.querySelectorAll('[data-review-note]')];
            const mediaFilterButtons = [...document.querySelectorAll('[data-media-filter]')];
            const activeReviewKeys = new Set(buttons.map((button) => button.dataset.reviewKey));
            const count = document.getElementById('decisionCount');
            const entryFor = (key) => {
              const value = state[key];
              if (typeof value === 'string') return { action: value, note: '' };
              return value || { action: '', note: '' };
            };
            const save = () => localStorage.setItem(storageKey, JSON.stringify(state));
            const saveView = () => localStorage.setItem(viewStorageKey, JSON.stringify(viewState));
            const activeMediaFilters = () => new Set(Array.isArray(viewState.mediaFilters) && viewState.mediaFilters.length
              ? viewState.mediaFilters
              : ['new', 'active_used']);
            const refreshMediaFilters = () => {
              const active = activeMediaFilters();
              mediaFilterButtons.forEach((button) => {
                const selected = active.has(button.dataset.mediaFilter);
                button.classList.toggle('active', selected);
                button.setAttribute('aria-pressed', String(selected));
              });
              document.querySelectorAll('.media-panel[data-disposition]').forEach((panel) => {
                const isOutput = panel.dataset.assetClass === 'output';
                const candidateHeld = ['candidate', 'held'].includes(panel.dataset.disposition) && active.has('candidate_held');
                const isNew = panel.dataset.newSinceLastReview === 'true' && active.has('new');
                panel.hidden = !(isNew || active.has(panel.dataset.disposition) || candidateHeld || (isOutput && active.has('outputs')));
              });
              document.querySelectorAll('.asset-role-group').forEach((group) => {
                const visible = [...group.querySelectorAll('.media-panel[data-disposition]')].some((panel) => !panel.hidden);
                group.hidden = !visible;
              });
            };
            mediaFilterButtons.forEach((button) => button.addEventListener('click', () => {
              const active = activeMediaFilters();
              if (active.has(button.dataset.mediaFilter)) active.delete(button.dataset.mediaFilter);
              else active.add(button.dataset.mediaFilter);
              viewState.mediaFilters = [...active];
              saveView();
              refreshMediaFilters();
            }));
            const refresh = () => {
              buttons.forEach((button) => {
                const selected = entryFor(button.dataset.reviewKey).action === button.dataset.reviewChoice;
                button.classList.toggle('active', selected);
                button.setAttribute('aria-pressed', String(selected));
              });
              notes.forEach((note) => {
                if (document.activeElement !== note) note.value = entryFor(note.dataset.reviewNote).note || '';
              });
              const decided = [...new Set(buttons.map((button) => button.dataset.reviewKey))].filter((key) => entryFor(key).action).length;
              const total = new Set(buttons.map((button) => button.dataset.reviewKey)).size;
              count.textContent = `${decided} / ${total} recorded`;
            };
            buttons.forEach((button) => button.addEventListener('click', () => {
              if (button.dataset.reviewChoice === 'select_candidate') {
                Object.keys(state).forEach((key) => {
                  if (key !== button.dataset.reviewKey && activeReviewKeys.has(key) && entryFor(key).action === 'select_candidate') delete state[key];
                });
              }
              const current = entryFor(button.dataset.reviewKey);
              state[button.dataset.reviewKey] = {
                ...current,
                ...decisionMetadata[button.dataset.reviewKey],
                review_mode: button.dataset.reviewMode,
                action: button.dataset.reviewChoice,
                card_id: button.dataset.reviewCard,
                section_id: button.dataset.reviewSection || null,
                scope_mode: button.dataset.reviewScopeMode,
                affected_section_ids: button.dataset.reviewAffectedSections.split(',').filter(Boolean),
                stage_id: button.dataset.reviewStage,
                revision_id: button.dataset.reviewRevision,
                decision_scope: button.dataset.reviewScope,
                revision_scope: button.dataset.revisionScope,
                review_target_id: button.dataset.reviewTarget,
                review_target_level: button.dataset.reviewLevel,
                review_target_number: button.dataset.reviewNumber,
                planning_cut_id: button.dataset.reviewPlanningCut || null,
                core_cut_id: button.dataset.reviewCoreCut || null,
                branch_cut_id: button.dataset.reviewBranchCut || null
              };
              save();
              refresh();
            }));
            notes.forEach((note) => note.addEventListener('input', () => {
              const current = entryFor(note.dataset.reviewNote);
              state[note.dataset.reviewNote] = { ...current, note: note.value };
              save();
            }));
            const listInputs = [...document.querySelectorAll('[data-review-list]')];
            listInputs.forEach((input) => input.addEventListener('input', () => {
              const current = entryFor(input.dataset.reviewList);
              const field = input.dataset.reviewListField;
              const values = [...new Set(input.value.split(/[\\n,]+/).map((value) => value.trim()).filter(Boolean))];
              state[input.dataset.reviewList] = { ...current, [field]: values };
              save();
            }));
            const copyText = async (text) => {
              if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
              const area = document.createElement('textarea');
              area.value = text;
              area.style.position = 'fixed';
              area.style.opacity = '0';
              document.body.appendChild(area);
              area.select();
              document.execCommand('copy');
              area.remove();
            };
            const payload = () => ({
                schema_version: 'idol-html-review-board.decision-export.v12',
                review_mode: #{JSON.generate(review_mode)},
                board_id: #{JSON.generate(board.fetch('board_id'))},
                board_revision: #{board_revision},
                manifest_path: #{JSON.generate(manifest_rel)},
                manifest_sha256: #{@manifest_sha256.to_json},
                decisions: Object.entries(state).map(([review_key, value]) => {
                  const entry = typeof value === 'string' ? { action: value } : value;
                  return { review_key, ...entry };
                }).filter((entry) => activeReviewKeys.has(entry.review_key) && (entry.action || entry.note))
              });
            document.getElementById('copyDecisions').addEventListener('click', async (event) => {
              await copyText(JSON.stringify(payload(), null, 2));
              event.currentTarget.textContent = 'Copied';
              setTimeout(() => { event.currentTarget.textContent = 'Copy JSON'; }, 1200);
            });
            const download = document.getElementById('downloadDecisions');
            if (download) download.addEventListener('click', () => {
              const blob = new Blob([JSON.stringify(payload(), null, 2)], { type: 'application/json' });
              const link = document.createElement('a');
              link.href = URL.createObjectURL(blob);
              link.download = `#{h(board.fetch('board_id'))}-r#{board_revision}-decisions.json`;
              link.click();
              URL.revokeObjectURL(link.href);
            });
            const cycles = [...document.querySelectorAll('details.review-cycle')];
            cycles.forEach((cycle) => {
              if (Object.prototype.hasOwnProperty.call(viewState.openGroups || {}, cycle.id)) {
                cycle.open = Boolean(viewState.openGroups[cycle.id]);
              }
            });
            document.querySelectorAll('.asset-role-group').forEach((group) => {
              const saved = (viewState.assetRoleGroups || {})[group.dataset.roleGroup];
              if (typeof saved === 'boolean') group.open = saved;
            });
            const hydrateCycleMedia = (cycle) => {
              cycle.querySelectorAll('img[data-src],video[data-src]').forEach((media) => {
                media.src = media.dataset.src;
                media.removeAttribute('data-src');
              });
            };
            cycles.filter((cycle) => cycle.open).forEach(hydrateCycleMedia);
            cycles.forEach((cycle) => cycle.addEventListener('toggle', () => {
              if (cycle.open) hydrateCycleMedia(cycle);
              viewState.openGroups = Object.fromEntries(cycles.map((item) => [item.id, item.open]));
              saveView();
            }));
            document.querySelectorAll('.asset-role-group').forEach((group) => group.addEventListener('toggle', () => {
              viewState.assetRoleGroups = {...(viewState.assetRoleGroups || {}), [group.dataset.roleGroup]: group.open};
              saveView();
            }));
            document.getElementById('expandAll')?.addEventListener('click', () => cycles.forEach((cycle) => { cycle.open = true; hydrateCycleMedia(cycle); }));
            document.getElementById('collapseAll')?.addEventListener('click', () => cycles.forEach((cycle) => { cycle.open = false; }));
            let pendingOnly = false;
            document.getElementById('showPending')?.addEventListener('click', (event) => {
              pendingOnly = !pendingOnly;
              document.querySelectorAll('.review-card').forEach((card) => {
                card.hidden = pendingOnly && (card.dataset.reviewable !== 'true' || Boolean(entryFor(card.dataset.reviewKey).action));
              });
              event.currentTarget.textContent = pendingOnly ? 'Show all' : 'Show pending only';
              event.currentTarget.setAttribute('aria-pressed', String(pendingOnly));
            });
            refreshMediaFilters();
            refresh();
          })();
        </script>
      </body>
      </html>
    HTML
  end

  # Cooperative writers share one persistent lock. Rechecks detect drift;
  # this is not a boundary against a same-user writer that ignores the lock.
  def write!
    html = render_html
    temporary = nil
    temporary_identity = nil
    temporary_io = nil
    lock = nil
    guard_output_route!
    lock_path = @output_path.dirname.join(".#{@output_path.basename}.lock")
    reject_symlink_components!(lock_path, "output lock")
    if lock_path.exist? && !lock_path.lstat.file?
      raise ReviewBoardContractError, "output lock is not a regular file"
    end
    lock = File.open(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW | File::NONBLOCK, 0o644)
    raise ReviewBoardContractError, "output lock is not a regular file" unless lock.stat.file?
    lock.flock(File::LOCK_EX)
    verify_lock_identity!(lock, lock_path)
    guard_output_route!
    verify_output_snapshot!
    output_sha256 = Digest::SHA256.hexdigest(html)
    temporary, temporary_io = allocate_output_temp!
    temporary_identity = file_identity(temporary_io.stat)
    temporary_io.write(html)
    temporary_io.flush
    temporary_io.fsync
    temporary_io.close
    temporary_io = nil
    recheck_bound_inputs!
    guard_output_route!
    verify_lock_identity!(lock, lock_path)
    verify_output_snapshot!
    unless file_identity(temporary.lstat) == temporary_identity && !temporary.symlink?
      raise ReviewBoardContractError, "owned output temporary file changed before publish"
    end
    _temporary_bytes, temporary_sha256 = checked_file_read(temporary, "owned output temporary", retain_bytes: false)
    unless temporary_sha256 == output_sha256
      raise ReviewBoardContractError, "owned output temporary bytes changed before publish"
    end
    File.rename(temporary, @output_path)
    temporary = nil
    @expected_output = output_snapshot!
    unless @expected_output.fetch(:sha256) == output_sha256
      raise ReviewBoardContractError, "published output changed before readback"
    end
    {
      "status" => "rendered",
      "output_path" => relative_to_repo(@output_path),
      "output_sha256" => output_sha256,
      "manifest_path" => relative_to_repo(@manifest_path),
      "manifest_sha256" => @manifest_sha256,
      "board_revision" => @manifest.dig("board", "revision"),
      "source_count" => @source_rows.length,
      "section_count" => if @workbench
        @manifest.fetch("sections").flat_map { |section| section.fetch("covered_section_ids") }.uniq.length
      else
        @manifest.fetch("sections").length
      end,
      "review_cycle_count" => @workbench ? @manifest.fetch("sections").length : 1,
      "card_count" => @manifest.fetch("sections").sum { |section| section.fetch("cards").length }
    }
  ensure
    temporary_io&.close unless temporary_io&.closed?
    if temporary && temporary_identity
      begin
        stat = temporary.lstat
        File.unlink(temporary) if !stat.symlink? && file_identity(stat) == temporary_identity
      rescue Errno::ENOENT
        nil
      end
    end
    lock&.close unless lock&.closed?
  end

  private

  def validate_run!
    run = @manifest["run"]
    expect_hash(run, "run")
    expect_keys(run, RUN_KEYS, RUN_KEYS, "run")
    run_root_text = expect_string(run["run_root"], "run.run_root")
    @run_root = checked_repo_path(run_root_text, "run.run_root", type: :directory)
    content_id = expect_string(run["content_id"], "run.content_id")
    raise ReviewBoardContractError, "run.content_id must equal run_root basename" unless @run_root.basename.to_s == content_id

    manifest_root = @run_root.join("review", "manifests").cleanpath
    unless inside?(@manifest_path, manifest_root)
      raise ReviewBoardContractError, "manifest must live under run review/manifests/: #{relative_to_repo(manifest_root)}"
    end
  end

  def validate_board!
    board = @manifest["board"]
    expect_hash(board, "board")
    required = %w[board_id stage_id review_mode status layout_profile legacy_cycle_aliases revision active_cycle_id storage_scope output_policy title purpose review_question target_summary message_summary whole_film_flow_summary section_flow_summary storyline_alignment_policy output_path]
    expect_keys(board, required, BOARD_KEYS, "board")
    expect_id(board["board_id"], "board.board_id")
    expect_string(board["stage_id"], "board.stage_id")
    expect_member(board["review_mode"], CYCLE_KINDS, "board.review_mode")
    expect_member(board["status"], %w[draft internal_review founder_review hold passed rejected superseded], "board.status")
    expected_profile = "founder-production-workbench-v12"
    expect_equal(board["layout_profile"], expected_profile, "board.layout_profile")
    aliases = expect_hash(board["legacy_cycle_aliases"], "board.legacy_cycle_aliases")
    expect_keys(aliases, LEGACY_CYCLE_ALIASES.keys, LEGACY_CYCLE_ALIASES.keys, "board.legacy_cycle_aliases")
    unless aliases == LEGACY_CYCLE_ALIASES
      raise ReviewBoardContractError, "board.legacy_cycle_aliases must retain the exact display/read-only alias map"
    end
    if @workbench
      %w[revision active_cycle_id storage_scope output_policy].each do |key|
        raise ReviewBoardContractError, "board missing required key: #{key}" unless board.key?(key)
      end
      unless board["revision"].is_a?(Integer) && board["revision"].positive?
        raise ReviewBoardContractError, "board.revision must be a positive integer"
      end
      expect_id(board["active_cycle_id"], "board.active_cycle_id")
      expect_equal(board["storage_scope"], "stable_board_lineage", "board.storage_scope")
      expect_equal(board["output_policy"], "replace_generated_projection_same_path", "board.output_policy")
    end
    expect_member(board.fetch("density", "comfortable"), %w[comfortable compact], "board.density")
    %w[title purpose review_question target_summary message_summary whole_film_flow_summary section_flow_summary].each do |key|
      validate_binding(board[key], "board.#{key}")
    end
    storyline_policy = expect_hash(board["storyline_alignment_policy"], "board.storyline_alignment_policy")
    policy_keys = %w[progression_rule visual_mismatch_action exact_source_projection]
    expect_keys(storyline_policy, policy_keys, policy_keys, "board.storyline_alignment_policy")
    expect_equal(
      storyline_policy["progression_rule"],
      "g00_through_g70_cumulative_exact_storyline_and_screen_progression_projection",
      "board.storyline_alignment_policy.progression_rule"
    )
    expect_equal(
      storyline_policy["visual_mismatch_action"],
      "reinspect_exact_bound_pixels_with_founder_reconcile_the_smallest_storyline_owner_then_reproject_only_affected_descendants",
      "board.storyline_alignment_policy.visual_mismatch_action"
    )
    expect_equal(storyline_policy["exact_source_projection"], true, "board.storyline_alignment_policy.exact_source_projection")
    validate_binding(board["eyebrow"], "board.eyebrow") if board.key?("eyebrow")
    Array(board.fetch("notices", [])).each_with_index do |notice, index|
      expect_hash(notice, "board.notices[#{index}]")
      expect_keys(notice, %w[tone text], NOTICE_KEYS, "board.notices[#{index}]")
      expect_member(notice["tone"], %w[info warning hold pass], "board.notices[#{index}].tone")
      validate_binding(notice["text"], "board.notices[#{index}].text")
    end

    output_text = expect_string(board["output_path"], "board.output_path")
    raise ReviewBoardContractError, "board.output_path must end in .html" unless output_text.end_with?(".html")
    @output_path = checked_repo_path(output_text, "board.output_path", type: :output)
    review_root = @run_root.join("review").cleanpath
    manifest_root = review_root.join("manifests")
    unless inside?(@output_path, review_root) && !inside?(@output_path, manifest_root)
      raise ReviewBoardContractError, "board.output_path must be a review HTML outside review/manifests"
    end
    expected_output_path = review_root.join("founder-workbench.html").cleanpath
    unless @output_path == expected_output_path
      raise ReviewBoardContractError,
            "board.output_path must be the run's single stable review path: #{relative_to_repo(expected_output_path)}"
    end

    return unless @continuity_profile

    expect_equal(board["projection_profile"], CONTINUITY_PROFILE, "board.projection_profile")
    expect_equal(board["projection_revision"], board["revision"], "board.projection_revision")
    if board.key?("source_set_digest")
      digest = expect_hash(board["source_set_digest"], "board.source_set_digest")
      expect_keys(digest, SOURCE_SET_DIGEST_KEYS, SOURCE_SET_DIGEST_KEYS, "board.source_set_digest")
      expect_equal(digest["algorithm"], "sha256", "board.source_set_digest.algorithm")
      expect_equal(digest["basis"], "canonical_projection_query_and_owner_bindings_v1", "board.source_set_digest.basis")
      expect_sha(digest["sha256"], "board.source_set_digest.sha256")
      unless digest["entry_count"].is_a?(Integer) && digest["entry_count"].positive?
        raise ReviewBoardContractError, "board.source_set_digest.entry_count must be a positive integer"
      end
    end
    last_reviewed = board["last_reviewed_revision"]
    unless last_reviewed.is_a?(Integer) && last_reviewed >= 0 && last_reviewed <= board.fetch("revision")
      raise ReviewBoardContractError, "board.last_reviewed_revision must be between zero and board.revision"
    end
    phases = expect_array(board["review_sequence"], "board.review_sequence", minimum: 1)
    seen_phases = {}
    seen_orders = {}
    phases.each_with_index do |phase, index|
      phase_label = "board.review_sequence[#{index}]"
      expect_hash(phase, phase_label)
      expect_keys(phase, REVIEW_PHASE_KEYS, REVIEW_PHASE_KEYS, phase_label)
      phase_id = expect_member(phase["phase"], %w[fp_close planning_02a post_02a], "#{phase_label}.phase")
      raise ReviewBoardContractError, "duplicate board review phase #{phase_id}" if seen_phases[phase_id]
      seen_phases[phase_id] = phase
      order = phase["order"]
      raise ReviewBoardContractError, "#{phase_label}.order must be a unique positive integer" unless order.is_a?(Integer) && order.positive? && !seen_orders[order]
      seen_orders[order] = true
      expect_string(phase["stage_id"], "#{phase_label}.stage_id")
      expected_gate = {"fp_close" => "read_only_fp_close_lineage", "planning_02a" => "active_02a_final_planning", "post_02a" => "read_only_projection"}.fetch(phase_id)
      expect_equal(phase["gate"], expected_gate, "#{phase_label}.gate")
    end
    if seen_phases["planning_02a"]
      raise ReviewBoardContractError, "planning_02a review requires read-only fp_close first" unless seen_phases["fp_close"] && seen_phases["fp_close"].fetch("order") < seen_phases["planning_02a"].fetch("order")
    end
    rollback = expect_hash(board["rollback_pair"], "board.rollback_pair")
    expect_keys(rollback, ROLLBACK_PAIR_KEYS, ROLLBACK_PAIR_KEYS, "board.rollback_pair")
    ROLLBACK_PAIR_KEYS.each { |key| validate_artifact_binding(rollback.fetch(key), "board.rollback_pair.#{key}") }
  end

  def validate_review_assets!
    assets = expect_array(@manifest["review_assets"], "review_assets", minimum: 1)
    board_revision = @manifest.dig("board", "revision")
    last_reviewed = @manifest.dig("board", "last_reviewed_revision")
    pending_relations = []
    assets.each_with_index do |asset, index|
      label = "review_assets[#{index}]"
      expect_hash(asset, label)
      expect_keys(asset, REVIEW_ASSET_KEYS - %w[note receipt], REVIEW_ASSET_KEYS, label)
      asset_id = expect_id(asset["asset_id"], "#{label}.asset_id")
      raise ReviewBoardContractError, "duplicate review asset id #{asset_id}" if @review_assets.key?(asset_id)
      first_seen = asset["first_seen_board_revision"]
      unless first_seen.is_a?(Integer) && first_seen.positive? && first_seen <= board_revision
        raise ReviewBoardContractError, "#{label}.first_seen_board_revision must be within the board lineage"
      end
      %w[supersedes_asset_id superseded_by_asset_id].each do |key|
        value = asset[key]
        next if value.nil?
        expect_id(value, "#{label}.#{key}")
        raise ReviewBoardContractError, "#{label}.#{key} cannot reference itself" if value == asset_id
        pending_relations << [asset_id, key, value]
      end
      expect_string(asset["original_owner"], "#{label}.original_owner")
      normalized = {
        "asset_id" => asset_id,
        "surface_locator" => asset.fetch("surface_locator"),
        "path" => asset.fetch("canonical_path"),
        "sha256" => asset.fetch("sha256"),
        "alt" => asset.fetch("alt"),
        "label" => asset.fetch("label"),
        "media_type" => asset.fetch("media_kind"),
        "role" => asset.fetch("role"),
        "inspection_action" => asset.fetch("inspection_action"),
        "display_lane" => asset.fetch("display_lane")
      }
      normalized["note"] = asset["note"] if asset.key?("note")
      normalized["receipt"] = asset["receipt"] if asset.key?("receipt")
      validate_media(normalized, label)
      physical_identity = [
        relative_to_repo(@resolved_media.fetch(normalized.object_id)),
        resolve_text(asset.fetch("sha256"), "#{label}.sha256")
      ]
      previous_asset_id = @review_asset_physical_identities[physical_identity]
      if previous_asset_id && previous_asset_id != asset_id
        raise ReviewBoardContractError,
              "#{label} reuses canonical path/hash already owned by #{previous_asset_id}; add a typed binding to the existing asset instead"
      end
      @review_asset_physical_identities[physical_identity] = asset_id
      binding_rows = expect_array(asset["bindings"], "#{label}.bindings", minimum: 1)
      bindings = {}
      binding_rows.each_with_index do |binding, binding_index|
        binding_label = "#{label}.bindings[#{binding_index}]"
        expect_hash(binding, binding_label)
        expect_keys(binding, REVIEW_ASSET_BINDING_KEYS - %w[section_id planning_cut_id core_cut_id branch_cut_id], REVIEW_ASSET_BINDING_KEYS, binding_label)
        binding_id = expect_id(binding["binding_id"], "#{binding_label}.binding_id")
        raise ReviewBoardContractError, "duplicate binding id #{binding_id} for #{asset_id}" if bindings.key?(binding_id)
        assignment = expect_member(binding["assignment_state"], %w[unassigned assigned], "#{binding_label}.assignment_state")
        target_level = expect_member(binding["target_level"], %w[unassigned discovery direction whole_film section planning_cut core_cut branch_cut 03v edit], "#{binding_label}.target_level")
        source_stage = expect_member(binding["source_stage"], %w[front_planning 01 02A 02B generated_branch_review 03V 04], "#{binding_label}.source_stage")
        lane_role = expect_member(binding["lane_role"], LANE_ROLES, "#{binding_label}.lane_role")
        disposition = expect_member(binding["disposition"], ASSET_DISPOSITIONS, "#{binding_label}.disposition")
        review_state = expect_member(binding["review_state"], ASSET_REVIEW_STATES, "#{binding_label}.review_state")
        unless binding["declared_order"].is_a?(Integer) && binding["declared_order"] >= 0
          raise ReviewBoardContractError, "#{binding_label}.declared_order must be a non-negative integer"
        end
        latest = binding["latest_binding_revision"]
        unless latest.is_a?(Integer) && latest >= first_seen && latest <= board_revision
          raise ReviewBoardContractError, "#{binding_label}.latest_binding_revision must stay inside the asset and board lineage"
        end
        unless binding["new_since_last_review"] == true || binding["new_since_last_review"] == false
          raise ReviewBoardContractError, "#{binding_label}.new_since_last_review must be boolean"
        end
        expected_new = first_seen > last_reviewed || latest > last_reviewed
        unless binding["new_since_last_review"] == expected_new
          raise ReviewBoardContractError, "#{binding_label}.new_since_last_review must be derived from declared board revisions"
        end
        if assignment == "unassigned"
          unless binding["target_id"].nil? && target_level == "unassigned" && lane_role == "unassigned" && disposition == "new" && review_state == "pending" && binding["new_since_last_review"]
            raise ReviewBoardContractError, "#{binding_label} unassigned intake must remain new, pending, and targetless"
          end
        else
          expect_id(binding["target_id"], "#{binding_label}.target_id")
          raise ReviewBoardContractError, "#{binding_label} assigned binding cannot use unassigned target or lane" if target_level == "unassigned" || lane_role == "unassigned"
        end
        if lane_role == "edit_output" && source_stage != "04"
          raise ReviewBoardContractError, "#{binding_label} edit_output must project from stage 04"
        end
        if lane_role == "playback_output" && source_stage != "03V"
          raise ReviewBoardContractError, "#{binding_label} playback_output must project from stage 03V"
        end
        if lane_role == "storyboard_output" && source_stage != "03V"
          raise ReviewBoardContractError, "#{binding_label} storyboard_output must project from stage 03V"
        end
        if lane_role == "generated_output" && !%w[02B generated_branch_review].include?(source_stage)
          raise ReviewBoardContractError, "#{binding_label} generated_output must project from 02B or generated Branch review"
        end
        %w[section_id planning_cut_id core_cut_id branch_cut_id].each { |key| expect_string(binding[key], "#{binding_label}.#{key}") if binding.key?(key) }
        validate_artifact_binding(binding.fetch("state_receipt"), "#{binding_label}.state_receipt")
        bindings[binding_id] = binding
        @review_asset_bindings[[asset_id, binding_id]] = binding
      end
      @review_assets[asset_id] = {"record" => asset, "media" => normalized, "bindings" => bindings}
    end
    pending_relations.each do |asset_id, key, target_id|
      raise ReviewBoardContractError, "review asset #{asset_id}.#{key} references missing asset #{target_id}" unless @review_assets.key?(target_id)
    end
  end

  def validate_sources!
    sources = expect_array(@manifest["sources"], "sources", minimum: 1)
    seen = {}
    sources.each_with_index do |row, index|
      label = "sources[#{index}]"
      expect_hash(row, label)
      expect_keys(row, SOURCE_KEYS, SOURCE_KEYS, label)
      source_id = expect_id(row["source_id"], "#{label}.source_id")
      raise ReviewBoardContractError, "duplicate source_id: #{source_id}" if seen[source_id]
      seen[source_id] = true
      path = checked_repo_path(expect_string(row["path"], "#{label}.path"), "#{label}.path", type: :file)
      sha = expect_sha(row["sha256"], "#{label}.sha256")
      document = load_document(path, label)
      actual = @bound_inputs.fetch(path.to_s).fetch(:sha256)
      raise ReviewBoardContractError, "#{label} SHA-256 mismatch for #{relative_to_repo(path)}" unless actual == sha
      expect_string(row["role"], "#{label}.role")
      @source_rows[source_id] = row
      @source_documents[source_id] = document
    end
  end

  def validate_decisions!
    decisions = expect_array(@manifest["decision_options"], "decision_options", minimum: 1)
    seen = {}
    decisions.each_with_index do |row, index|
      label = "decision_options[#{index}]"
      expect_hash(row, label)
      expect_keys(row, DECISION_KEYS, DECISION_KEYS, label)
      id = expect_id(row["id"], "#{label}.id")
      raise ReviewBoardContractError, "duplicate decision id: #{id}" if seen[id]
      seen[id] = true
      expect_string(row["label"], "#{label}.label")
      expect_member(row["tone"], %w[neutral pass hold revise reject], "#{label}.tone")
    end
    expected = case @review_mode
               when "g00_direction_draft"
                 [
                   {"id" => "attracted", "label" => "ATTRACTED", "tone" => "pass"},
                   {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
                   {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
                   {"id" => "connect_these", "label" => "CONNECT THESE", "tone" => "neutral"},
                   {"id" => "keep_only", "label" => "KEEP ONLY", "tone" => "neutral"},
                   {"id" => "search_further", "label" => "SEARCH FURTHER", "tone" => "revise"},
                   {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
                 ]
               when "g30_fp_final"
                 [
                   {"id" => "select_candidate", "label" => "SELECT COMPLETE ROUTE", "tone" => "pass"},
                   {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
                   {"id" => "reject", "label" => "REJECT", "tone" => "reject"},
                   {"id" => "direct_comment", "label" => "DIRECT COMMENT", "tone" => "neutral"}
                 ]
               when "g30_experiment_disposition"
                 [
                   {"id" => "reject_archive", "label" => "REJECT ARCHIVE", "tone" => "reject"},
                   {"id" => "revise_experiment", "label" => "REVISE EXPERIMENT", "tone" => "revise"},
                   {"id" => "teaser_only", "label" => "TEASER ONLY", "tone" => "pass"},
                   {"id" => "teaser_first_full_mv_hold", "label" => "TEASER FIRST · FULL MV HOLD", "tone" => "hold"},
                   {"id" => "full_mv_development", "label" => "FULL MV DEVELOPMENT", "tone" => "pass"},
                   {"id" => "hold", "label" => "HOLD", "tone" => "hold"}
                 ]
               when "video_playback_internal"
                 [
                   {"id" => "internal_pass", "label" => "CDD PLAYBACK PASS", "tone" => "pass"},
                   {"id" => "internal_hold", "label" => "CDD PLAYBACK HOLD", "tone" => "hold"},
                   {"id" => "material_exception", "label" => "MATERIAL EXCEPTION", "tone" => "revise"}
                 ]
               else
                 [
                   {"id" => "pass", "label" => "PASS", "tone" => "pass"},
                   {"id" => "hold", "label" => "HOLD", "tone" => "hold"},
                   {"id" => "reject", "label" => "REJECT", "tone" => "reject"}
                 ]
               end
    raise ReviewBoardContractError, "decision_options do not match #{@review_mode} review mode" unless decisions == expected
  end

  def validate_sections!
    sections = expect_array(@manifest["sections"], "sections", minimum: 1)
    if !@workbench && sections.length != 1
      raise ReviewBoardContractError, "section-cards-v1 requires exactly one active section"
    end
    section_ids = {}
    cycle_ids = {}
    revision_ids = {}
    supersedes = []
    sections.each_with_index do |section, section_index|
      label = "sections[#{section_index}]"
      expect_hash(section, label)
      expect_keys(section, %w[cycle_id cycle_kind review_mode scope_mode covered_section_ids stage_id revision_id status open_by_default decision_owner decision_question legal_actions affected_scope blocking_effect decision_epoch dispatch_id returned_output director_review founder_lineage worker_evidence label headline summary cards], SECTION_KEYS, label)
      cycle_review_mode = expect_member(section["review_mode"], CYCLE_KINDS, "#{label}.review_mode")
      section_id = section.key?("section_id") ? expect_id(section["section_id"], "#{label}.section_id") : nil
      covered_section_ids = section_id ? [section_id] : []
      if @workbench
        %w[cycle_id review_mode scope_mode covered_section_ids stage_id revision_id status open_by_default].each do |key|
          raise ReviewBoardContractError, "#{label} missing required key: #{key}" unless section.key?(key)
        end
        scope_mode = expect_member(
          section["scope_mode"],
          %w[sectionless single_section multi_section whole_film],
          "#{label}.scope_mode"
        )
        covered_section_ids = expect_array(
          section["covered_section_ids"],
          "#{label}.covered_section_ids",
          minimum: 0
        )
        if covered_section_ids.uniq.length != covered_section_ids.length
          raise ReviewBoardContractError, "#{label}.covered_section_ids must be unique"
        end
        covered_section_ids.each_with_index do |covered_id, covered_index|
          expect_string(covered_id, "#{label}.covered_section_ids[#{covered_index}]")
          unless SECTION_ID_RE.match?(covered_id)
            raise ReviewBoardContractError, "#{label}.covered_section_ids[#{covered_index}] must be a visual section id"
          end
        end
        case scope_mode
        when "sectionless"
          raise ReviewBoardContractError, "#{label} sectionless cycle cannot declare section_id" if section_id
          raise ReviewBoardContractError, "#{label} sectionless cycle cannot cover visual sections" unless covered_section_ids.empty?
          if %w[g30_fp_final g40_core_branch_authorization g50_branch_results video_playback_internal g60_playback_edit g70_release].include?(cycle_review_mode)
            raise ReviewBoardContractError, "#{label} #{cycle_review_mode} cannot be sectionless"
          end
        when "single_section"
          unless section_id && covered_section_ids.length == 1 && covered_section_ids.first == section_id
            raise ReviewBoardContractError, "#{label} single_section must cover exactly its section_id"
          end
        when "multi_section"
          raise ReviewBoardContractError, "#{label} multi_section requires section_id" unless section_id
          if covered_section_ids.length < 2
            raise ReviewBoardContractError, "#{label} multi_section must cover at least two section ids"
          end
        when "whole_film"
          unless section_id == "WHOLE_FILM"
            raise ReviewBoardContractError, "#{label} whole_film must use section_id WHOLE_FILM"
          end
        end
        cycle_id = expect_id(section["cycle_id"], "#{label}.cycle_id")
        raise ReviewBoardContractError, "duplicate cycle_id: #{cycle_id}" if cycle_ids[cycle_id]
        cycle_ids[cycle_id] = true
        expect_string(section["stage_id"], "#{label}.stage_id")
        revision_id = expect_id(section["revision_id"], "#{label}.revision_id")
        raise ReviewBoardContractError, "duplicate revision_id: #{revision_id}" if revision_ids[revision_id]
        revision_ids[revision_id] = true
        expect_member(section["status"], %w[draft internal_review founder_review hold passed rejected superseded], "#{label}.status")
        validate_cycle_contract!(section, label, covered_section_ids)
        unless section["open_by_default"] == true || section["open_by_default"] == false
          raise ReviewBoardContractError, "#{label}.open_by_default must be boolean"
        end
        if section.key?("supersedes_revision_id")
          superseded_revision_id = expect_id(section["supersedes_revision_id"], "#{label}.supersedes_revision_id")
          supersedes << [revision_id, superseded_revision_id]
        end
      else
        raise ReviewBoardContractError, "duplicate section_id: #{section_id}" if section_ids[section_id]
        section_ids[section_id] = true
      end
      %w[label headline summary].each { |key| validate_binding(section[key], "#{label}.#{key}") }
      validate_facts(section.fetch("facts", []), "#{label}.facts")
      expect_array(section.fetch("audit_notes", []), "#{label}.audit_notes").each_with_index do |value, index|
        validate_binding(value, "#{label}.audit_notes[#{index}]")
      end
      cards = expect_array(section["cards"], "#{label}.cards", minimum: 1)
      card_ids = {}
      cards.each_with_index do |card, card_index|
        validate_card(
          card,
          "#{label}.cards[#{card_index}]",
          card_ids,
          covered_section_ids: covered_section_ids,
          review_mode: cycle_review_mode,
          cycle: section
        )
      end
      if @continuity_profile
        phase_order = cards.map { |card| card.fetch("review_phase") }
        if phase_order.include?("planning_02a")
          first_02a = phase_order.index("planning_02a")
          unless phase_order.first(first_02a).all? { |phase| phase == "fp_close" } && phase_order.drop(first_02a).none? { |phase| phase == "fp_close" }
            raise ReviewBoardContractError, "#{label} must present every read-only FP Close storyline card before 02A Final Planning cards"
          end
        end
      end
      cycle_target_ids = section.fetch("affected_scope").fetch("target_ids")
      card_target_ids = cards.map { |card| card.fetch("review_target").fetch("target_id") }
      unless card_target_ids.all? { |target_id| cycle_target_ids.include?(target_id) }
        raise ReviewBoardContractError, "#{label}.affected_scope.target_ids must include every card review target"
      end
      cycle_chunk_ids = section.fetch("affected_scope").fetch("chunk_ids")
      unless card_target_ids.all? { |target_id| cycle_chunk_ids.include?(target_id) }
        raise ReviewBoardContractError, "#{label}.affected_scope.chunk_ids must include every card review target"
      end
      if cycle_review_mode == "g00_direction_draft"
        validate_exploratory_targets!(cards, label, cycle_review_mode)
      elsif cycle_review_mode == "g30_fp_final"
        validate_exploratory_targets!(cards, label, cycle_review_mode)
        validate_g30_cards!(section, cards, label)
      else
        validate_review_hierarchy!(cards, label, covered_section_ids)
      end
    end
    if @workbench
      active_cycle_id = @manifest.dig("board", "active_cycle_id").to_s
      raise ReviewBoardContractError, "board.active_cycle_id must name one sections[].cycle_id" unless cycle_ids[active_cycle_id]
      active_cycle = sections.find { |section| section["cycle_id"] == active_cycle_id }
      unless active_cycle && active_cycle["review_mode"] == @review_mode
        raise ReviewBoardContractError, "board.review_mode must equal the active review cycle mode"
      end
      supersedes.each do |revision_id, superseded_revision_id|
        unless revision_ids[superseded_revision_id]
          raise ReviewBoardContractError, "#{revision_id} supersedes missing revision #{superseded_revision_id}"
        end
      end
      option_ids = @manifest.fetch("decision_options").map { |row| row.fetch("id") }
      raise ReviewBoardContractError, "active review mode has no decision options" if option_ids.empty?
      order = sections.map { |section| CYCLE_ORDER.fetch(section.fetch("cycle_kind")) }
      unless order.each_cons(2).all? { |left, right| left <= right }
        raise ReviewBoardContractError, "sections must preserve cumulative G-cycle order"
      end
    end
  end

  def validate_card(card, label, card_ids, covered_section_ids:, review_mode:, cycle:)
    expect_hash(card, label)
    required = %w[card_id title direction screen_proof storyline_readout review_question decision_question decision_owner legal_actions affected_scope blocking_effect decision_epoch dispatch_id returned_output director_review founder_lineage worker_evidence decision_scope revision_scope affected_section_ids review_target source_field_refs media]
    expect_keys(card, required, CARD_KEYS, label)
    card_id = expect_id(card["card_id"], "#{label}.card_id")
    raise ReviewBoardContractError, "duplicate card_id: #{card_id}" if card_ids[card_id]
    card_ids[card_id] = true
    %w[title direction screen_proof review_question].each { |key| validate_binding(card[key], "#{label}.#{key}") }
    if @continuity_profile
      raise ReviewBoardContractError, "#{label}.screen_summary is required by the continuity projection" unless card.key?("screen_summary")
      validate_binding(card["screen_summary"], "#{label}.screen_summary")
      phase = expect_member(card["review_phase"], %w[fp_close planning_02a post_02a], "#{label}.review_phase")
      phase_state = expect_member(card["phase_state"], %w[active provisional read_only], "#{label}.phase_state")
      declared_phases = @manifest.dig("board", "review_sequence").map { |row| row.fetch("phase") }
      raise ReviewBoardContractError, "#{label}.review_phase is absent from board.review_sequence" unless declared_phases.include?(phase)
      if phase == "fp_close" && phase_state != "read_only"
        raise ReviewBoardContractError, "#{label} internal FP Close lineage must be read_only"
      elsif phase == "planning_02a" && !%w[provisional active].include?(phase_state)
        raise ReviewBoardContractError, "#{label} 02A Final Planning phase must be provisional or active"
      elsif phase == "post_02a" && phase_state != "read_only"
        raise ReviewBoardContractError, "#{label} post-02A phase must be read_only"
      end
    end
    validate_binding(card["decision_question"], "#{label}.decision_question")
    validate_binding(card["eyebrow"], "#{label}.eyebrow") if card.key?("eyebrow")
    expect_member(card.fetch("variant", "primary"), %w[primary alternate context hold recommendation candidate_alternative incompatible_alternative], "#{label}.variant")
    if card.key?("card_type")
      expect_member(card["card_type"], %w[candidate_route section_major_stack major_scene sequence_unit scene_phase creative_experiment sequence_candidate_set sequence_composition core_visual_candidate_set derivative_route production_scope core_slot core_cut branch_cut source_candidate member_visual prompt_packet video_input], "#{label}.card_type")
    end
    expect_member(card["route_id"], %w[FP-A FP-B FP-C], "#{label}.route_id") if card.key?("route_id")
    if @hierarchical_workbench
      raise ReviewBoardContractError, "#{label}.review_target is required" unless card["review_target"].is_a?(Hash)
      raise ReviewBoardContractError, "#{label}.affected_section_ids is required" unless card["affected_section_ids"].is_a?(Array)
    end
    expect_member(card["decision_scope"], %w[creative_selection reference_link screen_truth render_candidate video_prompt playback edit], "#{label}.decision_scope")
    validate_card_contract!(card, label, cycle, covered_section_ids)
    expect_member(card["revision_scope"], %w[none whole_film section planning_cut core_cut branch_cut], "#{label}.revision_scope")
    if card.key?("affected_section_ids")
      affected_section_ids = expect_array(
        card["affected_section_ids"],
        "#{label}.affected_section_ids",
        minimum: %w[g30_fp_final g40_core_branch_authorization g50_branch_results video_playback_internal g60_playback_edit g70_release].include?(review_mode) ? 1 : 0
      )
      if affected_section_ids.uniq.length != affected_section_ids.length
        raise ReviewBoardContractError, "#{label}.affected_section_ids must be unique"
      end
      affected_section_ids.each_with_index do |affected_id, index|
        expect_string(affected_id, "#{label}.affected_section_ids[#{index}]")
        unless SECTION_ID_RE.match?(affected_id)
          raise ReviewBoardContractError, "#{label}.affected_section_ids[#{index}] must be a visual section id"
        end
        unless covered_section_ids.include?(affected_id)
          raise ReviewBoardContractError, "#{label}.affected_section_ids contains #{affected_id} outside its review cycle"
        end
      end
    end
    expect_array(card["source_field_refs"], "#{label}.source_field_refs", minimum: 1).each_with_index do |pointer, index|
      validate_pointer(pointer, "#{label}.source_field_refs[#{index}]")
      resolve_pointer(pointer, "#{label}.source_field_refs[#{index}]")
    end
    validate_storyline_readout(
      card.fetch("storyline_readout"),
      "#{label}.storyline_readout",
      card.fetch("review_target"),
      review_mode
    )
    validate_facts(card.fetch("facts", []), "#{label}.facts")
    media = expect_array(card["media"], "#{label}.media", minimum: 1)
    inspection_actions = []
    media.each_with_index do |row, index|
      media_label = "#{label}.media[#{index}]"
      if @continuity_profile
        expect_hash(row, media_label)
        expect_keys(row, ASSET_REFERENCE_KEYS, ASSET_REFERENCE_KEYS, media_label)
        asset_id = expect_id(row["asset_id"], "#{media_label}.asset_id")
        binding_id = expect_id(row["binding_id"], "#{media_label}.binding_id")
        asset = @review_assets[asset_id]
        raise ReviewBoardContractError, "#{media_label} references unknown review asset #{asset_id}" unless asset
        binding = asset.fetch("bindings")[binding_id]
        raise ReviewBoardContractError, "#{media_label} references unknown binding #{binding_id}" unless binding
        target_id = card.fetch("review_target").fetch("target_id")
        if binding.fetch("assignment_state") == "assigned" && binding.fetch("target_id") != target_id
          raise ReviewBoardContractError, "#{media_label} binding target must equal card review target #{target_id}"
        end
        inspection_actions << asset.fetch("media").fetch("inspection_action")
      else
        validate_media(row, media_label)
        inspection_actions << row.fetch("inspection_action")
      end
    end
    if card.dig("storyline_readout", "mismatch_state") == "reinspect_required"
      unless inspection_actions.any? { |action| %w[inspect_and_create_or_revise_receipt pixel_review_generated_output].include?(action) }
        raise ReviewBoardContractError, "#{label} visual-reading mismatch must reopen an exact bound pixel inspection action"
      end
    end
    target_level = card.dig("review_target", "level")
    expected_scope = {"discovery" => "none", "direction" => "none"}.fetch(target_level, target_level)
    unless card["revision_scope"] == expected_scope
      raise ReviewBoardContractError, "#{label}.revision_scope must equal its review target level"
    end
  end

  def validate_storyline_readout(readout, label, review_target, review_mode)
    expect_hash(readout, label)
    required = %w[alignment_level progression_depth title source_field_ref source_value_sha256 visual_relationship exact_source_projection visual_mismatch_action mismatch_state]
    expect_keys(readout, required, STORYLINE_READOUT_KEYS, label)
    alignment_level = expect_member(
      readout["alignment_level"],
      %w[whole_film section planning_cut core_cut branch_cut],
      "#{label}.alignment_level"
    )
    expected_depth = {
      "g00_direction_draft" => "whole_film",
      "g10_song_lock" => "whole_film",
      "g20_visual_identity_lock" => "whole_film_and_sections",
      "g30_fp_final" => "whole_film_and_sections",
      "g30_experiment_disposition" => "whole_film_and_sections",
      "g40_core_branch_authorization" => "whole_film_sections_and_cuts",
      "g50_branch_results" => "whole_film_sections_and_cuts",
      "video_playback_internal" => "whole_film_sections_and_cuts",
      "g60_playback_edit" => "whole_film_sections_and_cuts",
      "g70_release" => "whole_film_sections_and_cuts"
    }.fetch(review_mode)
    expect_equal(readout["progression_depth"], expected_depth, "#{label}.progression_depth")
    validate_binding(readout["title"], "#{label}.title")
    validate_binding(readout["visual_relationship"], "#{label}.visual_relationship")
    validate_binding(readout["mismatch_note"], "#{label}.mismatch_note") if readout.key?("mismatch_note")
    expect_equal(readout["exact_source_projection"], true, "#{label}.exact_source_projection")
    expect_equal(
      readout["visual_mismatch_action"],
      "reinspect_exact_bound_pixels_with_founder_reconcile_the_smallest_storyline_owner_then_reproject_only_affected_descendants",
      "#{label}.visual_mismatch_action"
    )
    mismatch_state = expect_member(
      readout["mismatch_state"],
      %w[aligned reinspect_required reconciled],
      "#{label}.mismatch_state"
    )
    if mismatch_state == "reinspect_required" && !readout.key?("mismatch_note")
      raise ReviewBoardContractError, "#{label}.mismatch_note is required when exact pixels must be reinspected"
    end

    pointer = readout["source_field_ref"]
    validate_pointer(pointer, "#{label}.source_field_ref")
    source_value = resolve_pointer(pointer, "#{label}.source_field_ref")
    unless (source_value.is_a?(Hash) || source_value.is_a?(Array)) && !source_value.empty?
      raise ReviewBoardContractError, "#{label}.source_field_ref must resolve to a nonempty detailed storyline object or array"
    end
    expected_sha = value_sha256(source_value)
    unless expect_sha(readout["source_value_sha256"], "#{label}.source_value_sha256") == expected_sha
      raise ReviewBoardContractError, "#{label}.source_value_sha256 is stale"
    end

    target_level = review_target.fetch("level")
    allowed_alignment_levels = {
      "discovery" => %w[whole_film],
      "direction" => %w[whole_film section],
      "whole_film" => %w[whole_film],
      "section" => %w[section],
      "planning_cut" => %w[planning_cut],
      "core_cut" => %w[planning_cut core_cut],
      "branch_cut" => %w[planning_cut branch_cut]
    }.fetch(target_level)
    unless allowed_alignment_levels.include?(alignment_level)
      raise ReviewBoardContractError, "#{label}.alignment_level does not match review target #{target_level}"
    end
  end

  def validate_cycle_contract!(cycle, label, covered_section_ids)
    cycle_kind = expect_member(cycle.fetch("cycle_kind"), CYCLE_KINDS, "#{label}.cycle_kind")
    expected_mode = CYCLE_KIND_MODE.fetch(cycle_kind)
    expect_equal(cycle.fetch("review_mode"), expected_mode, "#{label}.review_mode for cycle_kind #{cycle_kind}")
    owner = validate_decision_owner(cycle.fetch("decision_owner"), "#{label}.decision_owner", cycle_kind)
    validate_binding(cycle.fetch("decision_question"), "#{label}.decision_question")
    validate_legal_actions(cycle.fetch("legal_actions"), expected_mode, "#{label}.legal_actions")
    scope = validate_affected_scope(cycle.fetch("affected_scope"), "#{label}.affected_scope")
    expect_equal(scope.fetch("scope_mode"), cycle.fetch("scope_mode"), "#{label}.affected_scope.scope_mode")
    expect_equal(scope.fetch("stage_id"), cycle.fetch("stage_id"), "#{label}.affected_scope.stage_id")
    unless scope.fetch("section_ids") == covered_section_ids
      raise ReviewBoardContractError, "#{label}.affected_scope.section_ids must exact-copy covered_section_ids"
    end
    validate_blocking_effect(cycle.fetch("blocking_effect"), expected_mode, "#{label}.blocking_effect")
    epoch = expect_string(cycle.fetch("decision_epoch"), "#{label}.decision_epoch")
    expect_id(cycle.fetch("dispatch_id"), "#{label}.dispatch_id")
    validate_artifact_binding(cycle.fetch("returned_output"), "#{label}.returned_output")
    validate_director_review_binding(cycle.fetch("director_review"), "#{label}.director_review")
    validate_worker_evidence(cycle.fetch("worker_evidence"), "#{label}.worker_evidence", cycle.fetch("dispatch_id"), cycle.fetch("director_review"))
    validate_founder_lineage(cycle.fetch("founder_lineage"), "#{label}.founder_lineage")
    validate_fragment_ownership(cycle["fragment_ownership"], "#{label}.fragment_ownership") if cycle.key?("fragment_ownership")
    validate_board_merge(cycle["board_merge"], "#{label}.board_merge") if cycle.key?("board_merge")
    [owner, epoch]
  end

  def validate_card_contract!(card, label, cycle, covered_section_ids)
    cycle_kind = cycle.fetch("cycle_kind")
    review_mode = cycle.fetch("review_mode")
    owner = validate_decision_owner(card.fetch("decision_owner"), "#{label}.decision_owner", cycle_kind)
    cycle_owner = normalize_decision_owner(cycle.fetch("decision_owner"))
    unless owner.fetch("role") == cycle_owner.fetch("role") && owner.fetch("promotion_authority") == cycle_owner.fetch("promotion_authority")
      raise ReviewBoardContractError, "#{label}.decision_owner must match its review cycle owner"
    end
    validate_legal_actions(card.fetch("legal_actions"), review_mode, "#{label}.legal_actions")
    scope = validate_affected_scope(card.fetch("affected_scope"), "#{label}.affected_scope")
    expect_equal(scope.fetch("scope_mode"), cycle.fetch("scope_mode"), "#{label}.affected_scope.scope_mode")
    expect_equal(scope.fetch("stage_id"), cycle.fetch("stage_id"), "#{label}.affected_scope.stage_id")
    affected = card.fetch("affected_section_ids")
    unless scope.fetch("section_ids") == affected
      raise ReviewBoardContractError, "#{label}.affected_scope.section_ids must exact-copy affected_section_ids"
    end
    unless affected.all? { |section_id| covered_section_ids.include?(section_id) }
      raise ReviewBoardContractError, "#{label}.affected_section_ids contains a section outside its review cycle"
    end
    target_id = card.fetch("review_target").fetch("target_id")
    unless scope.fetch("target_ids").include?(target_id)
      raise ReviewBoardContractError, "#{label}.affected_scope.target_ids must include #{target_id}"
    end
    unless scope.fetch("chunk_ids").include?(target_id)
      raise ReviewBoardContractError, "#{label}.affected_scope.chunk_ids must include #{target_id}"
    end
    validate_blocking_effect(card.fetch("blocking_effect"), review_mode, "#{label}.blocking_effect")
    unless card.fetch("decision_epoch") == cycle.fetch("decision_epoch")
      raise ReviewBoardContractError, "#{label}.decision_epoch must exact-copy its review cycle epoch"
    end
    expect_id(card.fetch("dispatch_id"), "#{label}.dispatch_id")
    validate_artifact_binding(card.fetch("returned_output"), "#{label}.returned_output")
    validate_director_review_binding(card.fetch("director_review"), "#{label}.director_review")
    validate_worker_evidence(card.fetch("worker_evidence"), "#{label}.worker_evidence", card.fetch("dispatch_id"), card.fetch("director_review"))
    validate_founder_lineage(card.fetch("founder_lineage"), "#{label}.founder_lineage")
    validate_fragment_ownership(card["fragment_ownership"], "#{label}.fragment_ownership") if card.key?("fragment_ownership")
    validate_board_merge(card["board_merge"], "#{label}.board_merge") if card.key?("board_merge")
  end

  def normalize_decision_owner(owner)
    if owner.is_a?(Hash)
      role = owner.fetch("role")
      default_surface = role == "creative_development_director" ? "cdd_internal_checkpoint" : "overall_founder_conversation"
      {
        "role" => role,
        "surface" => owner.fetch("surface", default_surface.to_s),
        "promotion_authority" => owner.fetch("promotion_authority", role == "overall_director" ? "overall_final_acceptance" : "cannot_promote")
      }
    else
      role = owner.to_s
      {
        "role" => role,
        "surface" => role == "creative_development_director" ? "cdd_internal_checkpoint" : "overall_founder_conversation",
        "promotion_authority" => role == "overall_director" ? "overall_final_acceptance" : "cannot_promote"
      }
    end
  end

  def validate_decision_owner(owner, label, cycle_kind)
    normalized = normalize_decision_owner(owner)
    role = expect_member(normalized.fetch("role"), OWNER_ROLES, "#{label}.role")
    expected_role = cycle_kind == "video_playback_internal" ? "creative_development_director" : "overall_director"
    unless role == expected_role
      raise ReviewBoardContractError, "#{label}.role must be #{expected_role} for cycle_kind #{cycle_kind}"
    end
    expected_surface = {
      "creative_development_director" => "cdd_internal_checkpoint",
      "overall_director" => "overall_founder_conversation"
    }.fetch(role)
    unless normalized.fetch("surface") == expected_surface
      raise ReviewBoardContractError, "#{label}.surface must be #{expected_surface}"
    end
    expected_promotion = role == "overall_director" ? "overall_final_acceptance" : "cannot_promote"
    unless normalized.fetch("promotion_authority") == expected_promotion
      raise ReviewBoardContractError, "#{label}.promotion_authority must be #{expected_promotion}"
    end
    normalized
  end

  def validate_legal_actions(actions, review_mode, label)
    expect_array(actions, label, minimum: 1)
    expected = MODE_LEGAL_ACTIONS.fetch(review_mode)
    raise ReviewBoardContractError, "#{label} must exact-copy legal actions for #{review_mode}" unless actions == expected
  end

  def validate_blocking_effect(effect, review_mode, label)
    expected = MODE_BLOCKING_EFFECT.fetch(review_mode)
    expect_equal(effect, expected, label)
  end

  def validate_affected_scope(scope, label)
    expect_hash(scope, label)
    expect_keys(scope, %w[scope_mode stage_id section_ids chunk_ids target_ids], %w[scope_mode stage_id section_ids chunk_ids target_ids planning_cut_ids core_cut_ids branch_cut_ids edit_shard_ids], label)
    expect_member(scope["scope_mode"], %w[sectionless single_section multi_section whole_film], "#{label}.scope_mode")
    expect_string(scope["stage_id"], "#{label}.stage_id")
    sections = expect_array(scope["section_ids"], "#{label}.section_ids")
    unless sections.uniq.length == sections.length && sections.all? { |id| id.is_a?(String) && SECTION_ID_RE.match?(id) }
      raise ReviewBoardContractError, "#{label}.section_ids must contain unique visual section ids"
    end
    chunks = expect_array(scope["chunk_ids"], "#{label}.chunk_ids", minimum: 1)
    unless chunks.uniq.length == chunks.length && chunks.all? { |id| id.is_a?(String) && !id.strip.empty? }
      raise ReviewBoardContractError, "#{label}.chunk_ids must be unique non-empty ids"
    end
    targets = expect_array(scope["target_ids"], "#{label}.target_ids", minimum: 1)
    raise ReviewBoardContractError, "#{label}.target_ids must be unique non-empty ids" unless targets.uniq.length == targets.length && targets.all? { |id| id.is_a?(String) && !id.strip.empty? }
    %w[core_cut_ids branch_cut_ids edit_shard_ids].each do |key|
      next unless scope.key?(key)
      values = expect_array(scope[key], "#{label}.#{key}")
      raise ReviewBoardContractError, "#{label}.#{key} must be unique non-empty ids" unless values.uniq.length == values.length && values.all? { |id| id.is_a?(String) && !id.strip.empty? }
    end
    scope
  end

  def validate_artifact_binding(binding, label)
    expect_hash(binding, label)
    expect_keys(binding, %w[path sha256], %w[path sha256 role], label)
    path = checked_repo_path(expect_string(binding["path"], "#{label}.path"), "#{label}.path", type: :file)
    sha = expect_sha(binding["sha256"], "#{label}.sha256")
    actual = bind_file_hash!(path, label)
    raise ReviewBoardContractError, "#{label} SHA-256 mismatch for #{relative_to_repo(path)}" unless actual == sha
    expect_string(binding["role"], "#{label}.role") if binding.key?("role")
    binding
  end

  def validate_director_review_binding(binding, label)
    expect_hash(binding, label)
    expect_keys(binding, %w[path sha256 row], %w[path sha256 row pointer role], label)
    validate_artifact_binding(binding.slice("path", "sha256"), label)
    expect_string(binding["row"], "#{label}.row")
    expect_string(binding["pointer"], "#{label}.pointer") if binding.key?("pointer")
    expect_string(binding["role"], "#{label}.role") if binding.key?("role")
    binding
  end

  def validate_worker_evidence(evidence, label, dispatch_id, director_review)
    expect_hash(evidence, label)
    expect_keys(evidence, %w[applicability lineage_id attempt_id session_id director_dispatch_index], %w[applicability lineage_id attempt_id session_id director_dispatch_index], label)
    applicability = expect_member(evidence["applicability"], %w[worker_return mechanical_no_worker], "#{label}.applicability")
    expect_string(evidence["lineage_id"], "#{label}.lineage_id")
    attempt_id = expect_string(evidence["attempt_id"], "#{label}.attempt_id")
    session_id = evidence["session_id"]
    if applicability == "worker_return"
      expect_string(session_id, "#{label}.session_id")
    elsif !session_id.nil?
      raise ReviewBoardContractError, "#{label}.session_id must be null for mechanical_no_worker"
    end
    expect_id(dispatch_id, "#{label}.dispatch_id")
    index = evidence.fetch("director_dispatch_index")
    expect_hash(index, "#{label}.director_dispatch_index")
    expect_keys(index, %w[path sha256 row pointer], %w[path sha256 row pointer], "#{label}.director_dispatch_index")
    validate_artifact_binding(index.slice("path", "sha256"), "#{label}.director_dispatch_index")
    index_row = expect_string(index["row"], "#{label}.director_dispatch_index.row")
    expect_string(index["pointer"], "#{label}.director_dispatch_index.pointer")
    unless index_row.include?(attempt_id)
      raise ReviewBoardContractError, "#{label}.director_dispatch_index.row must identify attempt_id #{attempt_id}"
    end
    review_row = expect_string(director_review.fetch("row"), "#{label}.director_review.row")
    unless review_row.include?(attempt_id)
      raise ReviewBoardContractError, "#{label}.director_review.row must identify attempt_id #{attempt_id}"
    end
    evidence
  end

  def validate_founder_lineage(lineage, label)
    expect_hash(lineage, label)
    expect_keys(lineage, %w[founder_receipt decision_export decision_intake], %w[founder_receipt decision_export decision_intake], label)
    %w[founder_receipt decision_export decision_intake].each do |key|
      validate_artifact_binding(lineage.fetch(key), "#{label}.#{key}")
    end
    lineage
  end

  def validate_fragment_ownership(fragment, label)
    expect_hash(fragment, label)
    expect_keys(fragment, %w[owner path sha256], %w[owner path sha256 scope], label)
    expect_string(fragment["owner"], "#{label}.owner")
    validate_artifact_binding(fragment.slice("path", "sha256"), label)
    validate_affected_scope(fragment["scope"], "#{label}.scope") if fragment.key?("scope")
  end

  def validate_board_merge(merge, label)
    expect_hash(merge, label)
    expect_keys(merge, %w[coordinator path sha256 single_writer], %w[coordinator path sha256 single_writer], label)
    expect_equal(merge["coordinator"], "board_coordinator", "#{label}.coordinator")
    expect_equal(merge["single_writer"], true, "#{label}.single_writer")
    validate_artifact_binding(merge.slice("path", "sha256"), label)
  end

  def validate_exploratory_targets!(cards, label, review_mode)
    expected_level = review_mode == "g00_direction_draft" ? "discovery" : "direction"
    expected_prefix = review_mode == "g00_direction_draft" ? "D" : "R"
    targets = cards.each_with_index.map do |card, index|
      target_label = "#{label}.cards[#{index}].review_target"
      target = expect_hash(card["review_target"], target_label)
      expect_keys(target, %w[target_id level display_number label], REVIEW_TARGET_KEYS, target_label)
      expect_id(target["target_id"], "#{target_label}.target_id")
      expect_equal(target["level"], expected_level, "#{target_label}.level")
      number = expect_string(target["display_number"], "#{target_label}.display_number")
      raise ReviewBoardContractError, "#{target_label}.display_number must use #{expected_prefix} numbering" unless number.match?(/\A#{expected_prefix}[0-9]+\z/)
      expect_string(target["label"], "#{target_label}.label")
      forbidden = %w[parent_target_id section_id planning_cut_id core_cut_id branch_cut_id].select { |field| target.key?(field) }
      raise ReviewBoardContractError, "#{target_label} cannot declare #{forbidden.join(', ')}" unless forbidden.empty?
      target.fetch("target_id")
    end
    duplicate_ids = targets.group_by(&:itself).select { |_id, rows| rows.length > 1 }.keys
    raise ReviewBoardContractError, "#{label} has duplicate review target ids: #{duplicate_ids.join(', ')}" unless duplicate_ids.empty?
  end

  def validate_g30_cards!(cycle, cards, label)
    same_flow = Array(cycle.dig("g30_readiness", "hold_reasons")).include?("consecutive_same_flow")
    recommendations = cards.count { |card| card.fetch("variant", "primary") == "recommendation" }
    alternatives = cards.count { |card| %w[candidate_alternative incompatible_alternative].include?(card.fetch("variant", "primary")) }
    if same_flow
      unless recommendations.zero? && alternatives == 3 && cards.length == 3
        raise ReviewBoardContractError, "#{label} G-30 consecutive_same_flow hold forbids a ranked recommendation; three complete alternatives required"
      end
    else
      unless recommendations == 1 && alternatives == 2 && cards.length == 3
        raise ReviewBoardContractError, "#{label} G-30 requires exactly one recommendation and two complete alternatives"
      end
    end
    route_ids = cards.map do |card|
      expect_equal(card["card_type"], "candidate_route", "#{label}.cards.card_type")
      route_id = expect_member(card["route_id"], %w[FP-A FP-B FP-C], "#{label}.cards.route_id")
      readiness = expect_hash(card["route_readiness"], "#{label}.cards[#{route_id}].route_readiness")
      keys = %w[opening_to_ending_story_complete section_major_stacks_complete sequence_composition_sets_complete core_visual_candidate_sets_complete selected_exact_reference_or_waiver_complete required_hero_proof_complete actual_visual_present materially_distinct]
      expect_keys(readiness, keys, keys, "#{label}.cards[#{route_id}].route_readiness")
      %w[opening_to_ending_story_complete section_major_stacks_complete sequence_composition_sets_complete core_visual_candidate_sets_complete materially_distinct].each do |key|
        expect_equal(readiness[key], true, "#{label}.cards[#{route_id}].route_readiness.#{key}")
      end
      %w[selected_exact_reference_or_waiver_complete required_hero_proof_complete actual_visual_present].each do |key|
        unless [true, false].include?(readiness[key])
          raise ReviewBoardContractError, "#{label}.cards[#{route_id}].route_readiness.#{key} must be boolean"
        end
      end
      route_id
    end
    unless route_ids == %w[FP-A FP-B FP-C]
      raise ReviewBoardContractError, "#{label} G-30 cards must be ordered FP-A, FP-B, FP-C"
    end

    readiness = expect_hash(cycle["g30_readiness"], "#{label}.g30_readiness")
    keys = %w[route_ids complete_route_count route_candidate_set_complete routes_materially_distinct actual_visuals_present reference_complete hero_generated controls_enabled hold_reasons]
    expect_keys(readiness, keys, keys, "#{label}.g30_readiness")
    expect_equal(readiness["route_ids"], %w[FP-A FP-B FP-C], "#{label}.g30_readiness.route_ids")
    expect_equal(readiness["complete_route_count"], 3, "#{label}.g30_readiness.complete_route_count")
    route_rows = cards.map { |card| card.fetch("route_readiness") }
    derived = {
      "route_candidate_set_complete" => route_rows.all? { |row| %w[opening_to_ending_story_complete section_major_stacks_complete sequence_composition_sets_complete core_visual_candidate_sets_complete].all? { |key| row[key] == true } },
      "routes_materially_distinct" => route_rows.all? { |row| row["materially_distinct"] == true },
      "actual_visuals_present" => route_rows.all? { |row| row["actual_visual_present"] == true },
      "reference_complete" => route_rows.all? { |row| row["selected_exact_reference_or_waiver_complete"] == true },
      "hero_generated" => route_rows.all? { |row| row["required_hero_proof_complete"] == true }
    }
    derived.each { |key, value| expect_equal(readiness[key], value, "#{label}.g30_readiness.#{key}") }
    same_flow = Array(readiness["hold_reasons"]).include?("consecutive_same_flow")
    controls_enabled = derived.values.all? && !same_flow
    expect_equal(readiness["controls_enabled"], controls_enabled, "#{label}.g30_readiness.controls_enabled")
    expected_holds = []
    expected_holds << "fp_route_candidate_set_incomplete" unless derived["route_candidate_set_complete"] && derived["routes_materially_distinct"]
    expected_holds << "visual_missing" unless derived["actual_visuals_present"]
    expected_holds << "reference_incomplete" unless derived["reference_complete"]
    expected_holds << "g30_prepared_generation_authority_missing" unless derived["hero_generated"]
    expected_holds << "consecutive_same_flow" if same_flow
    expect_equal(readiness["hold_reasons"], expected_holds, "#{label}.g30_readiness.hold_reasons")
  end

  def validate_review_hierarchy!(cards, label, covered_section_ids)
    targets = cards.each_with_index.map do |card, index|
      target_label = "#{label}.cards[#{index}].review_target"
      target = expect_hash(card["review_target"], target_label)
      expect_keys(target, %w[target_id level display_number label], REVIEW_TARGET_KEYS, target_label)
      target_id = expect_id(target["target_id"], "#{target_label}.target_id")
      level = expect_member(target["level"], %w[whole_film section planning_cut core_cut branch_cut], "#{target_label}.level")
      number = expect_string(target["display_number"], "#{target_label}.display_number")
      raise ReviewBoardContractError, "#{target_label}.display_number must be a dotted numeric label" unless number.match?(/\A[0-9]+(?:\.[0-9]+){0,3}\z/)
      expected_depth = {"whole_film" => 1, "section" => 2, "planning_cut" => 3, "core_cut" => 3, "branch_cut" => 4}.fetch(level)
      unless number.split(".").length == expected_depth
        raise ReviewBoardContractError, "#{target_label}.display_number depth must match #{level}"
      end
      expect_string(target["label"], "#{target_label}.label")
      section_id = target["section_id"].to_s
      planning_cut_id = target["planning_cut_id"].to_s
      core_cut_id = target["core_cut_id"].to_s
      branch_cut_id = target["branch_cut_id"].to_s
      parent_id = target["parent_target_id"].to_s
      case level
      when "whole_film"
        unless [section_id, planning_cut_id, core_cut_id, branch_cut_id, parent_id].all?(&:empty?)
          raise ReviewBoardContractError, "#{target_label} whole_film target cannot carry parent, section, planning-cut, core-cut, or branch-cut ids"
        end
      when "section"
        raise ReviewBoardContractError, "#{target_label} section target requires section_id and parent_target_id only" if section_id.empty? || parent_id.empty? || !planning_cut_id.empty? || !core_cut_id.empty? || !branch_cut_id.empty?
      when "planning_cut"
        raise ReviewBoardContractError, "#{target_label} planning-cut target requires section_id, planning_cut_id, and parent_target_id" if section_id.empty? || planning_cut_id.empty? || parent_id.empty? || !core_cut_id.empty? || !branch_cut_id.empty?
      when "core_cut"
        raise ReviewBoardContractError, "#{target_label} core-cut target requires section_id, core_cut_id, and parent_target_id" if section_id.empty? || core_cut_id.empty? || parent_id.empty? || !planning_cut_id.empty? || !branch_cut_id.empty?
      when "branch_cut"
        raise ReviewBoardContractError, "#{target_label} branch-cut target requires section_id, core_cut_id, branch_cut_id, and parent_target_id" if section_id.empty? || core_cut_id.empty? || branch_cut_id.empty? || parent_id.empty? || !planning_cut_id.empty?
      end
      if !section_id.empty? && !covered_section_ids.include?(section_id)
        raise ReviewBoardContractError, "#{target_label}.section_id is outside the review cycle"
      end
      {
        "target_id" => target_id,
        "parent_target_id" => parent_id,
        "level" => level,
        "display_number" => number,
        "section_id" => section_id,
        "planning_cut_id" => planning_cut_id,
        "core_cut_id" => core_cut_id,
        "branch_cut_id" => branch_cut_id
      }
    end
    duplicate_ids = targets.map { |target| target.fetch("target_id") }.group_by(&:itself).select { |_id, rows| rows.length > 1 }.keys
    raise ReviewBoardContractError, "#{label} has duplicate review target ids: #{duplicate_ids.join(', ')}" unless duplicate_ids.empty?
    target_index = targets.to_h { |target| [target.fetch("target_id"), target] }
    roots = targets.select { |target| target.fetch("level") == "whole_film" }
    raise ReviewBoardContractError, "#{label} must contain exactly one whole_film review target root" unless roots.length == 1
    expected_parent_level = {"section" => "whole_film", "planning_cut" => "section", "core_cut" => "section", "branch_cut" => "core_cut"}
    targets.each do |target|
      target_id = target.fetch("target_id")
      parent_id = target.fetch("parent_target_id")
      level = target.fetch("level")
      next if level == "whole_film"

      parent = target_index[parent_id]
      raise ReviewBoardContractError, "#{label} review target #{target_id} has a missing parent #{parent_id}" unless parent
      unless parent.fetch("level") == expected_parent_level.fetch(level)
        raise ReviewBoardContractError, "#{label} review target #{target_id} must be nested under a #{expected_parent_level.fetch(level)} target"
      end
      unless target.fetch("display_number").start_with?("#{parent.fetch('display_number')}.")
        raise ReviewBoardContractError, "#{label} review target #{target_id} number must extend its parent number"
      end
      if %w[planning_cut core_cut branch_cut].include?(level) && target.fetch("section_id") != parent.fetch("section_id")
        raise ReviewBoardContractError, "#{label} review target #{target_id} must keep its parent section_id"
      end
      if level == "branch_cut" && target.fetch("core_cut_id") != parent.fetch("core_cut_id")
        raise ReviewBoardContractError, "#{label} review target #{target_id} must keep its parent core_cut_id"
      end
    end
  end

  def validate_facts(facts, label)
    expect_array(facts, label).each_with_index do |fact, index|
      fact_label = "#{label}[#{index}]"
      expect_hash(fact, fact_label)
      expect_keys(fact, %w[label value], FACT_KEYS, fact_label)
      expect_string(fact["label"], "#{fact_label}.label")
      validate_binding(fact["value"], "#{fact_label}.value")
      expect_member(fact.fetch("style", "text"), %w[text mono], "#{fact_label}.style")
    end
  end

  def validate_media(row, label)
    expect_hash(row, label)
    required = %w[asset_id surface_locator path sha256 alt label role inspection_action]
    required << "media_type" if @hierarchical_workbench
    expect_keys(row, required, MEDIA_KEYS, label)
    %w[asset_id path sha256 alt label].each { |key| validate_binding(row[key], "#{label}.#{key}") }
    surface = validate_surface_locator(row["surface_locator"], "#{label}.surface_locator")
    validate_binding(row["note"], "#{label}.note") if row.key?("note")
    role = expect_member(row["role"], %w[member_visual primary_reference supporting_reference context_reference generated_branch_cut storyboard_board playback edit_output diagnostic], "#{label}.role")
    expect_member(row["inspection_action"], %w[consume_bound_interpretation inspect_and_create_or_revise_receipt pixel_review_generated_output playback_review context_only], "#{label}.inspection_action")
    expect_member(row["display_lane"], %w[member_face member_styling reference output], "#{label}.display_lane") if row.key?("display_lane")
    if REFERENCE_ROLES.include?(role)
      raise ReviewBoardContractError, "#{label}.receipt is required for reference media" unless row["receipt"].is_a?(Hash)
    end
    validate_receipt(row["receipt"], "#{label}.receipt") if row.key?("receipt")

    media_type = expect_member(row.fetch("media_type", "image"), %w[image video], "#{label}.media_type")
    media_path_text = resolve_text(row["path"], "#{label}.path")
    media_path = checked_repo_path(media_path_text, "#{label}.path", type: :file)
    allowed_extensions = media_type == "video" ? VIDEO_EXTENSIONS : IMAGE_EXTENSIONS
    unless allowed_extensions.include?(media_path.extname.downcase)
      raise ReviewBoardContractError, "#{label}.path must be a supported #{media_type}"
    end
    expected_sha = expect_sha(resolve_text(row["sha256"], "#{label}.sha256"), "#{label}.sha256")
    actual_sha = bind_file_hash!(media_path, label)
    raise ReviewBoardContractError, "#{label} SHA-256 mismatch for #{relative_to_repo(media_path)}" unless expected_sha == actual_sha
    asset_id = resolve_text(row["asset_id"], "#{label}.asset_id")
    binding = {
      "path" => relative_to_repo(media_path),
      "sha256" => expected_sha,
      "source_asset_id" => surface.fetch("source_asset_id"),
      "selected_cell_or_frame_id" => surface.fetch("selected_cell_or_frame_id"),
      "surface_kind" => surface.fetch("surface_kind"),
      "source_timecode" => surface["source_timecode"]
    }
    if @asset_bindings.key?(asset_id) && @asset_bindings.fetch(asset_id) != binding
      raise ReviewBoardContractError, "#{label}.asset_id #{asset_id} is already bound to different image bytes or surface identity"
    end
    @asset_bindings[asset_id] = binding
    @resolved_media[row.object_id] = media_path
    @resolved_surfaces[row.object_id] = surface
  end

  def validate_surface_locator(locator, label)
    expect_hash(locator, label)
    required = %w[source_asset_id selected_cell_or_frame_id surface_kind]
    expect_keys(locator, required, SURFACE_LOCATOR_KEYS, label)
    required.each { |key| validate_binding(locator[key], "#{label}.#{key}") }
    validate_binding(locator["source_timecode"], "#{label}.source_timecode") if locator.key?("source_timecode")
    surface = {
      "source_asset_id" => resolve_text(locator["source_asset_id"], "#{label}.source_asset_id"),
      "selected_cell_or_frame_id" => resolve_text(locator["selected_cell_or_frame_id"], "#{label}.selected_cell_or_frame_id"),
      "surface_kind" => resolve_text(locator["surface_kind"], "#{label}.surface_kind")
    }
    surface["source_timecode"] = resolve_text(locator["source_timecode"], "#{label}.source_timecode") if locator.key?("source_timecode")
    expect_member(surface.fetch("surface_kind"), %w[full_image sequence_sheet sequence_sheet_cell scene_crop video_frame video_clip generated_branch_cut storyboard_board playback edit_output diagnostic], "#{label}.surface_kind")
    surface
  end

  def validate_receipt(receipt, label)
    expect_hash(receipt, label)
    required = %w[receipt_id source_identity disposition function follow_strength preserve discard]
    expect_keys(receipt, required, RECEIPT_KEYS, label)
    receipt.each { |key, value| validate_binding(value, "#{label}.#{key}") }
    expect_member(resolve_text(receipt["disposition"], "#{label}.disposition"), %w[applied combined held rejected], "#{label}.disposition")
    expect_member(resolve_text(receipt["follow_strength"], "#{label}.follow_strength"), %w[bounded_surface_direct full_scene_direct sequence_direct], "#{label}.follow_strength")
  end

  def validate_binding(value, label)
    if value.is_a?(Hash)
      validate_pointer(value, label)
      resolve_pointer(value, label)
    elsif value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      raise ReviewBoardContractError, "#{label} must not be blank" if value.is_a?(String) && value.strip.empty?
    else
      raise ReviewBoardContractError, "#{label} must be a scalar or source pointer"
    end
  end

  def validate_pointer(pointer, label)
    expect_hash(pointer, label)
    expect_keys(pointer, %w[source_id pointer], POINTER_KEYS, label)
    expect_string(pointer["source_id"], "#{label}.source_id")
    raw_pointer = pointer["pointer"]
    raise ReviewBoardContractError, "#{label}.pointer must be a JSON Pointer" unless raw_pointer.is_a?(String) && (raw_pointer.empty? || raw_pointer.start_with?("/"))
    raise ReviewBoardContractError, "#{label}.join must be a string" if pointer.key?("join") && !pointer["join"].is_a?(String)
  end

  def resolve_pointer(pointer, label)
    source_id = pointer.fetch("source_id")
    document = @source_documents[source_id]
    raise ReviewBoardContractError, "#{label} references unknown source_id #{source_id}" unless document
    raw_pointer = pointer.fetch("pointer")
    value = document
    unless raw_pointer.empty?
      raw_pointer.split("/")[1..].each do |raw_token|
        token = raw_token.gsub("~1", "/").gsub("~0", "~")
        if value.is_a?(Array)
          raise ReviewBoardContractError, "#{label} array pointer token is not an index: #{token}" unless token.match?(/\A(?:0|[1-9]\d*)\z/)
          index = token.to_i
          raise ReviewBoardContractError, "#{label} array pointer index is out of range: #{index}" if index >= value.length
          value = value[index]
        elsif value.is_a?(Hash)
          raise ReviewBoardContractError, "#{label} pointer key is missing: #{token}" unless value.key?(token)
          value = value[token]
        else
          raise ReviewBoardContractError, "#{label} pointer traverses a scalar at #{token}"
        end
      end
    end
    value
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        source_key = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_value(value[source_key])
      end
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def value_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end

  def resolve_text(binding, label)
    value = binding.is_a?(Hash) ? resolve_pointer(binding, label) : binding
    if value.is_a?(Array)
      joiner = binding.is_a?(Hash) ? binding.fetch("join", " · ") : " · "
      unless value.all? { |item| item.is_a?(String) || item.is_a?(Numeric) || item == true || item == false }
        raise ReviewBoardContractError, "#{label} resolves to a non-scalar array"
      end
      value.map(&:to_s).join(joiner)
    elsif value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
      value.to_s
    else
      raise ReviewBoardContractError, "#{label} resolves to a non-scalar value"
    end
  end

  # Export metadata is projected exactly from the active cycle/card contract;
  # the browser only records the Founder action and verbatim note.
  def decision_metadata_map
    return {} unless @workbench

    @manifest.fetch("sections").each_with_object({}) do |section, result|
      revision_id = section.fetch("revision_id")
      section.fetch("cards").each do |card|
        key = "#{revision_id}::#{card.fetch('card_id')}"
        result[key] = {
          "cycle_kind" => section.fetch("cycle_kind"),
          "decision_owner" => card.fetch("decision_owner"),
          "decision_question" => resolve_text(card.fetch("decision_question"), "#{card.fetch('card_id')}.decision_question"),
          "legal_actions" => card.fetch("legal_actions"),
          "affected_scope" => card.fetch("affected_scope"),
          "blocking_effect" => card.fetch("blocking_effect"),
          "decision_epoch" => card.fetch("decision_epoch"),
          "dispatch_id" => card.fetch("dispatch_id"),
          "returned_output" => card.fetch("returned_output"),
          "director_review" => card.fetch("director_review"),
          "founder_lineage" => card.fetch("founder_lineage"),
          "worker_evidence" => card.fetch("worker_evidence"),
          "review_phase" => card.fetch("review_phase", "post_02a")
        }
      end
    end
  end

  def resolve_media_reference(reference)
    return [reference, nil] unless @continuity_profile

    asset_id = reference.fetch("asset_id")
    binding_id = reference.fetch("binding_id")
    asset = @review_assets.fetch(asset_id)
    [asset.fetch("media"), asset.fetch("bindings").fetch(binding_id)]
  end

  def review_asset_display_rows
    return [] unless @continuity_profile

    @review_assets.values.map do |asset|
      bindings = asset.fetch("bindings").values
      display_binding = bindings.find { |binding| binding.fetch("new_since_last_review") } ||
                        bindings.max_by { |binding| [binding.fetch("latest_binding_revision"), binding.fetch("declared_order")] }
      [asset.fetch("media").fetch("display_lane"), asset.fetch("media"), display_binding]
    end.sort_by do |_lane, media, binding|
      [binding.fetch("new_since_last_review") ? 0 : 1, binding.fetch("declared_order"), media.fetch("asset_id")]
    end
  end

  def review_asset_counts
    rows = review_asset_display_rows
    counts = {
      "total" => rows.length,
      "new" => 0,
      "active_used" => 0,
      "candidate_held" => 0,
      "rejected" => 0,
      "superseded" => 0,
      "outputs" => 0
    }
    rows.each do |_lane, _media, binding|
      disposition = binding.fetch("disposition")
      counts["new"] += 1 if binding.fetch("new_since_last_review") || disposition == "new"
      counts["active_used"] += 1 if disposition == "active_used"
      counts["candidate_held"] += 1 if %w[candidate held].include?(disposition)
      counts["rejected"] += 1 if disposition == "rejected"
      counts["superseded"] += 1 if disposition == "superseded"
      counts["outputs"] += 1 if %w[generated_output storyboard_output playback_output edit_output].include?(binding.fetch("lane_role"))
    end
    counts
  end

  def render_review_asset_register
    rows = review_asset_display_rows
    counts = review_asset_counts
    labels = {
      "new_inbox" => "NEW SINCE LAST REVIEW",
      "governing_main" => "GOVERNING / MAIN",
      "support_job" => "NAMED SUPPORT JOBS",
      "context_alternative" => "CONTEXT / ALTERNATIVES",
      "member_identity" => "MEMBER IDENTITY",
      "generated_output" => "GENERATED OUTPUTS",
      "storyboard_output" => "STORYBOARD OUTPUTS",
      "playback_output" => "PLAYBACK OUTPUTS",
      "edit_output" => "EDIT OUTPUTS",
      "diagnostic" => "DIAGNOSTIC",
      "unassigned" => "UNASSIGNED"
    }
    grouped = rows.group_by do |_lane, _media, binding|
      binding.fetch("new_since_last_review") ? "new_inbox" : binding.fetch("lane_role")
    end
    groups = labels.map do |role, heading|
      group_rows = grouped[role]
      next if group_rows.nil? || group_rows.empty?
      open = role == "new_inbox" || %w[governing_main support_job generated_output].include?(role)
      <<~HTML
        <details class="asset-role-group register-role-group role-#{h(role)}" data-role-group="register-#{h(role)}"#{open ? " open" : ""}>
          <summary><span>#{h(heading)}</span><b>#{format('%02d', group_rows.length)}</b></summary>
          <div class="asset-register-grid">#{render_media_rows(group_rows, "review-assets")}</div>
        </details>
      HTML
    end.compact.join("\n")
    <<~HTML
      <section class="review-asset-register" aria-label="Pointer-only review asset register">
        <div class="asset-register-heading"><div><span>POINTER-ONLY REVIEW ASSET REGISTER</span><h2>Board revision #{@manifest.dig('board', 'revision')} · #{rows.length} accountable asset(s)</h2></div><p>Role and state come only from the owning lane receipt. Filters are local view state.</p></div>
        <div class="media-filter-row" role="toolbar" aria-label="Review asset state filters">
          <button type="button" data-media-filter="new" aria-pressed="false">NEW <b>#{counts.fetch('new')}</b></button>
          <button type="button" data-media-filter="active_used" aria-pressed="false">ACTIVE / USED <b>#{counts.fetch('active_used')}</b></button>
          <button type="button" data-media-filter="candidate_held" aria-pressed="false">CANDIDATE / HELD <b>#{counts.fetch('candidate_held')}</b></button>
          <button type="button" data-media-filter="rejected" aria-pressed="false">REJECTED <b>#{counts.fetch('rejected')}</b></button>
          <button type="button" data-media-filter="superseded" aria-pressed="false">SUPERSEDED <b>#{counts.fetch('superseded')}</b></button>
          <button type="button" data-media-filter="outputs" aria-pressed="false">OUTPUTS <b>#{counts.fetch('outputs')}</b></button>
        </div>
        <div class="asset-register-groups">#{groups}</div>
      </section>
    HTML
  end

  def render_section(section, index)
    id = section["section_id"] || section.fetch("cycle_id")
    cycle_id = @workbench ? section.fetch("cycle_id") : id
    label = resolve_text(section.fetch("label"), "#{id}.label")
    headline = resolve_text(section.fetch("headline"), "#{id}.headline")
    summary = resolve_text(section.fetch("summary"), "#{id}.summary")
    facts = render_facts(section.fetch("facts", []), "#{id}.facts")
    audits = section.fetch("audit_notes", []).map { |note| %(<li>#{text_html(resolve_text(note, "#{id}.audit"))}</li>) }.join
    reviewable = !@workbench || cycle_id == @manifest.dig("board", "active_cycle_id")
    open = !@workbench || section.fetch("open_by_default", true) || cycle_id == @manifest.dig("board", "active_cycle_id")
    previous_defer = @defer_media_loading
    @defer_media_loading = @continuity_profile && !open
    cards_html = section.fetch("cards").map { |card| render_card(card, section, reviewable: reviewable) }.join("\n")
    @defer_media_loading = previous_defer
    display_label = if @workbench
      scope_label = review_scope_label(section)
      covered = section.fetch("covered_section_ids")
      label == id || label == scope_label || covered.include?(label) ? scope_label : "#{scope_label} · #{label}"
    else
      label
    end
    body = <<~HTML
      <section class="review-section">
        <div class="section-heading">
          <div class="section-index">#{format('%02d', index + 1)}</div>
          <div><div class="section-label">#{h(display_label)}</div><h2>#{h(headline)}</h2></div>
        </div>
        <p class="section-summary">#{text_html(summary)}</p>
        #{facts}
        <div class="card-grid">#{cards_html}</div>
        #{audits.empty? ? "" : %(<div class="section-audit"><strong>SECTION AUDIT</strong><ul>#{audits}</ul></div>)}
      </section>
    HTML
    return body.sub('<section class="review-section">', %(<section id="#{h(id)}" class="review-section">)) unless @workbench

    stage_id = section.fetch("stage_id")
    revision_id = section.fetch("revision_id")
    status = section.fetch("status")
    supersedes = section["supersedes_revision_id"]
    <<~HTML
      <details id="#{h(cycle_id)}" class="review-cycle status-#{h(status)}" data-cycle-revision="#{h(revision_id)}"#{open ? " open" : ""}>
        <summary><span>#{h(review_scope_label(section))}</span><strong>#{h(headline)}</strong><code>#{h(stage_id)} · #{h(revision_id)} · #{h(status)}#{supersedes ? " · replaces #{h(supersedes)}" : ""}</code></summary>
        #{body}
      </details>
    HTML
  end

  def render_card(card, section, reviewable: true)
    section_id = section["section_id"]
    cycle_id = @workbench ? section.fetch("cycle_id") : section_id
    card_id = card.fetch("card_id")
    stage_id = @workbench ? section.fetch("stage_id") : @manifest.dig("board", "stage_id")
    revision_id = @workbench ? section.fetch("revision_id") : @manifest_sha256
    review_key = @workbench ? "#{revision_id}::#{card_id}" : card_id
    decision_scope = card.fetch("decision_scope", "creative_selection")
    revision_scope = card.fetch("revision_scope")
    scope_mode = @workbench ? section.fetch("scope_mode") : "single_section"
    affected_section_ids = card.fetch(
      "affected_section_ids",
      @workbench ? section.fetch("covered_section_ids") : [section_id]
    )
    review_target = card["review_target"] || {
      "target_id" => card_id,
      "level" => "section",
      "display_number" => "1.1",
      "label" => section_id,
      "section_id" => section_id
    }
    title = resolve_text(card.fetch("title"), "#{card_id}.title")
    eyebrow = card.key?("eyebrow") ? resolve_text(card["eyebrow"], "#{card_id}.eyebrow") : card_id
    direction = resolve_text(card.fetch("direction"), "#{card_id}.direction")
    screen_proof = resolve_text(card.fetch("screen_proof"), "#{card_id}.screen_proof")
    screen_summary = card.key?("screen_summary") ? resolve_text(card["screen_summary"], "#{card_id}.screen_summary") : screen_proof
    storyline_html = render_storyline_readout(card.fetch("storyline_readout"), card_id)
    question = resolve_text(card.fetch("review_question"), "#{card_id}.review_question")
    variant = card.fetch("variant", "primary")
    candidate_badge = if section.fetch("review_mode") == "g30_fp_final"
                        role = variant == "recommendation" ? "RECOMMENDED" : "ALTERNATIVE"
                        route = card.fetch("route_id")
                        route_readiness = card.fetch("route_readiness")
                        reference_badge = route_readiness.fetch("selected_exact_reference_or_waiver_complete") ? "REFERENCE COMPLETE" : "REFERENCE INCOMPLETE"
                        hero_badge = route_readiness.fetch("required_hero_proof_complete") ? "HERO GENERATED" : "HERO MISSING"
                        same_flow = Array(section.dig("g30_readiness", "hold_reasons")).include?("consecutive_same_flow")
                        flow_badge = same_flow ? %(<span class="readiness-badge">SAME FLOW HOLD</span>) : ""
                        %(<span>#{h(route)} · #{role}</span><span class="readiness-badge">#{h(reference_badge)}</span><span class="readiness-badge">#{h(hero_badge)}</span>#{flow_badge})
                      else
                        ""
                      end
    review_phase = card.fetch("review_phase", "post_02a")
    phase_state = card.fetch("phase_state", "active")
    if @continuity_profile && %w[fp_close planning_02a].include?(review_phase)
      reviewable &&= phase_state == "active"
    end
    g30_lock_reason = nil
    if section.fetch("review_mode") == "g30_fp_final" && !section.fetch("g30_readiness").fetch("controls_enabled")
      g30_lock_reason = section.fetch("g30_readiness").fetch("hold_reasons").join(" · ")
      reviewable = false
    end
    refs = card.fetch("source_field_refs").map { |ref| "#{ref.fetch('source_id')}##{ref.fetch('pointer')}" }
    media_rows = card.fetch("media").map do |media_ref|
      media, asset_state = resolve_media_reference(media_ref)
      lane = media.fetch("display_lane", default_display_lane(media, review_target.fetch("level")))
      [lane, media, asset_state]
    end
    media_layout = if review_target.fetch("level") == "core_cut"
                     member_rows = media_rows.select { |lane, _media, _state| %w[member_face member_styling].include?(lane) }
                     reference_rows = media_rows.reject { |lane, _media, _state| %w[member_face member_styling].include?(lane) }
                     member_html = if member_rows.empty?
                                     %(<div class="member-visual-empty">No member face or styling visual is attached to this Core-Cut review target.</div>)
                                   else
                                     render_member_visuals(member_rows, card_id)
                                   end
                     <<~HTML
                       <div class="core-visual-layout">
                         <aside class="member-visual-rail" aria-label="Member face and styling visuals">#{member_html}</aside>
                         <div class="core-reference-role-groups">#{render_role_grouped_media(reference_rows, card_id, "#{cycle_id}--#{card_id}")}</div>
                       </div>
                     HTML
                   elsif section.fetch("review_mode") == "g30_fp_final"
                     render_g30_sequence_parent_layout(media_rows, card_id)
                   else
                     %(<div class="media-gallery media-count-#{media_rows.length}">#{render_media_rows(media_rows, card_id)}</div>)
                   end
    facts_html = render_facts(card.fetch("facts", []), "#{card_id}.facts")
    facts_block = if card.fetch("facts", []).empty?
                    ""
                  else
                    %(<details class="secondary-pack facts-pack"><summary>Facts · #{card.fetch('facts', []).length}</summary>#{facts_html}</details>)
                  end
    meta_block = <<~META
      <details class="secondary-pack meta-pack">
        <summary>Contract / field refs · metadata</summary>
        #{render_decision_contract(card, section)}
        <details class="field-refs"><summary>Canonical field refs · #{refs.length}</summary><code>#{refs.map { |ref| h(ref) }.join("<br>")}</code></details>
      </details>
    META
    <<~HTML
      <article class="review-card variant-#{h(variant)} target-level-#{h(review_target.fetch('level'))}" id="#{h(cycle_id)}--#{h(card_id)}" data-review-key="#{h(review_key)}" data-reviewable="#{reviewable}" data-review-phase="#{h(review_phase)}" data-phase-state="#{h(phase_state)}">
        #{media_layout}
        <div class="card-copy">
          <div class="card-eyebrow"><b class="target-number">#{h(review_target.fetch('display_number'))}</b> #{h(review_target.fetch('label'))} · #{h(eyebrow)} #{candidate_badge}<span>#{h(affected_section_label(affected_section_ids, scope_mode))}</span></div>
          <h3>#{h(title)}</h3>
          #{storyline_html}
          <div class="screen-summary"><span>SCREEN / DECISION SUMMARY</span>#{text_html(screen_summary)}</div>
          <div class="judge-band">
            <div class="card-question"><span>#{reviewable ? review_prompt_label(section.fetch('review_mode')) : "PREVIOUS REVIEW CYCLE"}</span>#{text_html(question)}</div>
            #{!reviewable && review_phase == "planning_02a" && phase_state == "provisional" ? %(<div class="phase-order-hold">FP Close·01·02A의 정확한 연결이 준비될 때까지 이 범위는 HOLD입니다.</div>) : ""}
            #{reviewable ? %(<div class="decision-row">#{render_decision_buttons(card_id, review_key, section_id, scope_mode, affected_section_ids, stage_id, revision_id, decision_scope, revision_scope, review_target, section.fetch('review_mode'), review_phase)}</div>) : %(<div class="decision-locked">#{g30_lock_reason ? "G-30 FAIL-CLOSED · #{h(g30_lock_reason)}" : (review_phase == 'fp_close' ? 'Internal FP Close · exact read-only lineage' : 'Planning scope not ready or prior cycle · decision input disabled')}</div>)}
            #{@workbench && reviewable ? render_mode_inputs(review_key, section.fetch("review_mode")) : ""}
          </div>
          <details class="secondary-pack primary-detail-pack"><summary>Full Direction + Screen Proof · 2</summary><div class="read-stack" aria-label="Full production screen reading"><div class="direction"><span>DIRECTION</span>#{text_html(direction)}</div><div class="screen-proof"><span>SCREEN PROOF</span>#{text_html(screen_proof)}</div></div></details>
          #{facts_block}
          #{meta_block}
        </div>
      </article>
    HTML
  end

  def render_storyline_readout(readout, card_id)
    title = resolve_text(readout.fetch("title"), "#{card_id}.storyline_readout.title")
    relationship = resolve_text(
      readout.fetch("visual_relationship"),
      "#{card_id}.storyline_readout.visual_relationship"
    )
    value = resolve_pointer(
      readout.fetch("source_field_ref"),
      "#{card_id}.storyline_readout.source_field_ref"
    )
    mismatch_state = readout.fetch("mismatch_state")
    mismatch_note = readout.key?("mismatch_note") ? resolve_text(
      readout["mismatch_note"],
      "#{card_id}.storyline_readout.mismatch_note"
    ) : nil
    <<~HTML
      <section class="storyline-readout mismatch-#{h(mismatch_state)}" aria-label="Exact storyline reading paired with the visual">
        <div class="storyline-readout-head"><span>DIRECTOR STORYLINE · #{h(readout.fetch('alignment_level').tr('_', ' ').upcase)}</span><strong>#{h(title)}</strong><code>#{h(readout.fetch('progression_depth'))}</code></div>
        <div class="storyline-exact-value">#{render_storyline_value(value)}</div>
        <div class="storyline-visual-relationship"><span>HOW THIS TEXT READS THE VISUAL</span>#{text_html(relationship)}</div>
        #{mismatch_note ? %(<div class="storyline-mismatch-note"><span>PIXEL REINSPECTION NOTE</span>#{text_html(mismatch_note)}</div>) : ""}
      </section>
    HTML
  end

  def render_storyline_value(value)
    case value
    when Hash
      rows = value.map do |key, child|
        %(<div class="storyline-field"><dt>#{h(key.to_s.tr('_', ' '))}</dt><dd>#{render_storyline_value(child)}</dd></div>)
      end.join
      %(<dl class="storyline-object">#{rows}</dl>)
    when Array
      items = value.map { |child| %(<li>#{render_storyline_value(child)}</li>) }.join
      %(<ol class="storyline-list">#{items}</ol>)
    when NilClass
      %(<span class="storyline-null">—</span>)
    else
      text_html(value.to_s)
    end
  end

  def validated_surface_locator!(media)
    @resolved_surfaces.fetch(media.object_id) do
      raise ReviewBoardContractError, "media is missing a validated surface locator"
    end
  end

  def validated_media_path_text!(media)
    path = @resolved_media.fetch(media.object_id) do
      raise ReviewBoardContractError, "media is missing a validated path"
    end
    relative_to_repo(path)
  end

  def sequence_sheet_media?(media)
    surface = validated_surface_locator!(media)
    kind = surface.fetch("surface_kind")
    path = validated_media_path_text!(media)
    kind == "sequence_sheet" || path.end_with?("contact-sheet-5in1.png")
  end

  def core_mark_media?(media)
    role = media["role"].to_s
    return true if %w[selected_core core_mark primary_reference].include?(role)

    path = validated_media_path_text!(media)
    path.match?(%r{/frame-\d+}) && !sequence_sheet_media?(media)
  end

  def sequence_event_key(media)
    source_id = validated_surface_locator!(media).fetch("source_asset_id")
    unless source_id.is_a?(String) && !source_id.strip.empty?
      raise ReviewBoardContractError, "surface_locator.source_asset_id must be a resolved non-empty event identity"
    end
    source_id
  end

  def render_g30_sequence_parent_layout(media_rows, card_id)
    member_rows = media_rows.select { |lane, _media, _state| %w[member_face member_styling].include?(lane) }
    rest = media_rows.reject { |lane, _media, _state| %w[member_face member_styling].include?(lane) }
    sequence_rows = rest.select { |_lane, media, _state| sequence_sheet_media?(media) }
    if sequence_rows.empty?
      return %(<div class="media-gallery media-count-#{media_rows.length}">#{render_media_rows(media_rows, card_id)}</div>)
    end

    remaining = rest - sequence_rows
    core_rows = remaining.select { |_lane, media, _state| core_mark_media?(media) }
    other_rows = remaining - core_rows
    used_cores = []
    event_html = sequence_rows.each_with_index.map do |row, index|
      _lane, sheet, _state = row
      key = sequence_event_key(sheet)
      matched = core_rows.select { |_core_lane, core_media, _core_state| sequence_event_key(core_media) == key }
      used_cores.concat(matched)
      core_block = if matched.empty?
                     %(<p class="g30-core-marks-empty">This event sheet keeps one or two key Cores, not a start/middle/end dump.</p>)
                   else
                     %(<div class="g30-core-marks" aria-label="Key Cores for this event">#{render_media_rows(matched, card_id)}</div>)
                   end
      <<~HTML
        <section class="g30-event-block" data-event-key="#{h(key)}" data-event-index="#{index + 1}">
          <div class="g30-sequence-parent" aria-label="Major Sequence parent sheet">#{render_media_rows([row], card_id)}</div>
          #{core_block}
        </section>
      HTML
    end.join
    unmatched = core_rows - used_cores
    unmatched_html = unmatched.empty? ? "" : %(<div class="g30-related-hypotheses" aria-label="Unmatched Core stills">#{render_media_rows(unmatched, card_id)}</div>)
    other_html = other_rows.empty? ? "" : %(<div class="g30-related-hypotheses" aria-label="Related distinct Core hypotheses">#{render_media_rows(other_rows, card_id)}</div>)
    member_html = if member_rows.empty?
                    ""
                  else
                    %(<aside class="member-visual-rail" aria-label="Member face and styling visuals">#{render_member_visuals(member_rows, card_id)}</aside>)
                  end
    <<~HTML
      <div class="g30-sequence-core-layout" data-g30-layout="per_event_sequence_parent_core_marks">
        #{event_html}
        #{unmatched_html}
        #{other_html}
        #{member_html}
      </div>
    HTML
  end

  def render_media_rows(media_rows, label)
    total = media_rows.length
    media_rows.each_with_index.map do |(display_lane, media, asset_state), index|
      render_media(media, label, display_lane: display_lane, index: index + 1, total: total, asset_state: asset_state)
    end.join("\n")
  end

  def render_member_visuals(media_rows, label)
    face_rows = media_rows.select { |lane, _media, _state| lane == "member_face" }
    style_rows = media_rows.select { |lane, _media, _state| lane == "member_styling" }
    primary = [face_rows.first, style_rows.first].compact
    extras = face_rows.drop(1) + style_rows.drop(1)
    <<~HTML
      <div class="member-primary-grid">#{render_media_rows(primary, label)}</div>
      #{extras.empty? ? "" : %(<div class="member-style-strip" aria-label="Additional member styling visuals">#{render_media_rows(extras, label)}</div>)}
    HTML
  end

  def render_role_grouped_media(media_rows, source_label, id_prefix)
    labels = {
      "governing_main" => "GOVERNING / MAIN",
      "support_job" => "NAMED SUPPORT JOBS",
      "context_alternative" => "CONTEXT / ALTERNATIVES",
      "generated_output" => "GENERATED OUTPUTS",
      "storyboard_output" => "STORYBOARD OUTPUTS",
      "playback_output" => "PLAYBACK OUTPUTS",
      "edit_output" => "EDIT OUTPUTS",
      "diagnostic" => "DIAGNOSTIC",
      "member_identity" => "MEMBER IDENTITY",
      "unassigned" => "UNASSIGNED"
    }
    grouped = media_rows.group_by { |_lane, media, state| state&.fetch("lane_role", nil) || legacy_lane_role(media) }
    order = labels.keys
    order.map do |role|
      rows = grouped[role]
      next if rows.nil? || rows.empty?
      heading = labels.fetch(role)
      open = %w[governing_main support_job generated_output].include?(role)
      <<~HTML
        <details class="asset-role-group" data-role-group="#{h(role)}"#{open ? " open" : ""}>
          <summary><span>#{h(heading)}</span><b>#{format('%02d', rows.length)}</b></summary>
          #{render_media_carousel(rows, source_label, "#{id_prefix}--#{role}", visible_limit: 4, heading: heading)}
        </details>
      HTML
    end.join("\n")
  end

  def render_media_carousel(media_rows, source_label, carousel_id, visible_limit:, heading:)
    count = media_rows.length
    visible_slots = [[count, 1].max, visible_limit].min
    panels = count.zero? ? %(<div class="carousel-empty">No reference or output visual is attached.</div>) : render_media_rows(media_rows, source_label)
    <<~HTML
      <section class="media-carousel" data-carousel data-count="#{count}" style="--visible-slots:#{visible_slots}" aria-label="#{h(heading)}">
        <div class="carousel-head"><span>#{h(heading)}</span><span class="carousel-count">#{format('%02d', count)} IMAGES</span></div>
        <button class="carousel-arrow carousel-prev" type="button" data-carousel-prev aria-label="Previous images">&#8592;</button>
        <div id="#{h(carousel_id)}" class="core-reference-grid" data-carousel-track tabindex="0">#{panels}</div>
        <button class="carousel-arrow carousel-next" type="button" data-carousel-next aria-label="Next images">&#8594;</button>
        <div class="carousel-status" data-carousel-status aria-live="polite"></div>
      </section>
    HTML
  end

  def render_media(media, label, display_lane:, index:, total:, asset_state: nil)
    path = @resolved_media.fetch(media.object_id)
    surface = @resolved_surfaces.fetch(media.object_id)
    href = path.relative_path_from(@output_path.dirname).to_s
    asset_id = resolve_text(media.fetch("asset_id"), "#{label}.media.asset_id")
    media_label = resolve_text(media.fetch("label"), "#{label}.media.label")
    alt = resolve_text(media.fetch("alt"), "#{label}.media.alt")
    note = media.key?("note") ? resolve_text(media["note"], "#{label}.media.note") : ""
    sha = resolve_text(media.fetch("sha256"), "#{label}.media.sha256")
    receipt = media["receipt"]
    media_type = media.fetch("media_type", "image")
    source_attribute = @defer_media_loading ? %(data-src="#{h(href)}") : %(src="#{h(href)}")
    media_element = if media_type == "video"
                      %(<video controls preload="metadata" #{source_attribute} aria-label="#{h(alt)}"></video>)
                    else
                      %(<a href="#{h(href)}"><img class="zoomable" loading="lazy" #{source_attribute} alt="#{h(alt)}"></a>)
                    end
    state_attrs = if asset_state
      disposition = asset_state.fetch("disposition")
      lane_role = asset_state.fetch("lane_role")
      output = %w[generated_output storyboard_output playback_output edit_output].include?(lane_role)
      %( data-binding-id="#{h(asset_state.fetch('binding_id'))}" data-source-stage="#{h(asset_state.fetch('source_stage'))}" data-disposition="#{h(disposition)}" data-new-since-last-review="#{asset_state.fetch('new_since_last_review')}" data-review-state="#{h(asset_state.fetch('review_state'))}" data-lane-role="#{h(lane_role)}" data-asset-class="#{output ? 'output' : 'reference'}")
    else
      ""
    end
    state_badge = asset_state ? %(<span class="media-state-badge state-#{h(asset_state.fetch('disposition'))}">#{h(asset_state.fetch('disposition').tr('_', ' ').upcase)}</span>) : ""
    <<~HTML
      <figure class="media-panel role-#{h(media.fetch('role'))} surface-kind-#{h(surface.fetch('surface_kind'))} display-lane-#{h(display_lane)}" data-media-index="#{index}" data-media-total="#{total}"#{state_attrs}>
        <span class="media-index" aria-label="Image #{index} of #{total}">#{format('%02d', index)} / #{format('%02d', total)}</span>
        #{state_badge}
        #{media_element}
        <figcaption>
          <div class="media-caption-main"><strong>#{h(media_label)}</strong><span>#{h(asset_state ? asset_state.fetch('lane_role') : media.fetch('role'))}</span></div>
          #{note.empty? ? "" : %(<p class="media-note">#{text_html(note)}</p>)}
          <details class="media-meta">
            <summary>File / hash / surface</summary>
            <div class="media-file-binding">
              <span>FILE</span>
              <a href="#{h(href)}"><code>#{h(relative_to_repo(path))}</code></a>
              <span>SHA-256</span>
              <code>#{h(sha)}</code>
            </div>
            <div class="media-provenance-inline"><code>ASSET #{h(asset_id)} · SOURCE #{h(surface.fetch('source_asset_id'))} · #{h(surface.fetch('selected_cell_or_frame_id'))} · #{h(surface.fetch('surface_kind'))}#{surface['source_timecode'] ? " · #{h(surface['source_timecode'])}" : ""}</code></div>
              #{asset_state ? %(<div class="media-provenance-inline"><code>STAGE #{h(asset_state.fetch('source_stage'))} · TARGET #{h(asset_state.fetch('target_id') || 'UNASSIGNED')} · #{h(asset_state.fetch('review_state'))} · BINDING R#{asset_state.fetch('latest_binding_revision')}</code></div>) : ""}
            #{receipt ? render_receipt(receipt, label) : ""}
          </details>
        </figcaption>
      </figure>
    HTML
  end

  def default_display_lane(media, target_level)
    role = media.fetch("role")
    return "member_face" if role == "member_visual" && target_level == "core_cut"
    return "reference" if REFERENCE_ROLES.include?(role) || role == "context_reference"

    "output"
  end

  def legacy_lane_role(media)
    {
      "member_visual" => "member_identity",
      "primary_reference" => "governing_main",
      "supporting_reference" => "support_job",
      "context_reference" => "context_alternative",
      "generated_branch_cut" => "generated_output",
      "storyboard_board" => "storyboard_output",
      "playback" => "playback_output",
      "diagnostic" => "diagnostic"
    }.fetch(media.fetch("role"))
  end

  def render_receipt(receipt, label)
    fields = [
      ["receipt", resolve_text(receipt.fetch("receipt_id"), "#{label}.receipt.id")],
      ["source", resolve_text(receipt.fetch("source_identity"), "#{label}.receipt.source")],
      ["disposition", resolve_text(receipt.fetch("disposition"), "#{label}.receipt.disposition")],
      ["function", resolve_text(receipt.fetch("function"), "#{label}.receipt.function")],
      ["follow", resolve_text(receipt.fetch("follow_strength"), "#{label}.receipt.follow")],
      ["preserve", resolve_text(receipt.fetch("preserve"), "#{label}.receipt.preserve")],
      ["discard", resolve_text(receipt.fetch("discard"), "#{label}.receipt.discard")]
    ]
    rows = fields.map { |key, value| %(<dt>#{h(key)}</dt><dd>#{text_html(value)}</dd>) }.join
    %(<details class="receipt"><summary>Reference interpretation receipt</summary><dl>#{rows}</dl></details>)
  end

  def render_facts(facts, label)
    return "" if facts.empty?
    rows = facts.each_with_index.map do |fact, index|
      value = resolve_text(fact.fetch("value"), "#{label}[#{index}].value")
      style = fact.fetch("style", "text")
      %(<dt>#{h(fact.fetch('label'))}</dt><dd class="#{h(style)}">#{text_html(value)}</dd>)
    end.compact.join
    %(<dl class="fact-list">#{rows}</dl>)
  end

  def render_decision_contract(card, section)
    owner = normalize_decision_owner(card.fetch("decision_owner"))
    scope = card.fetch("affected_scope")
    lineage = card.fetch("founder_lineage")
    worker_evidence = card.fetch("worker_evidence")
    dispatch_index = worker_evidence.fetch("director_dispatch_index")
    rows = [
      ["DECISION OWNER", "#{owner.fetch('role')} · #{owner.fetch('surface')} · #{owner.fetch('promotion_authority')}"],
      ["DECISION QUESTION", resolve_text(card.fetch("decision_question"), "#{card.fetch('card_id')}.decision_question")],
      ["LEGAL ACTIONS", card.fetch("legal_actions").join(" · ")],
      ["AFFECTED SCOPE", "#{scope.fetch('scope_mode')} · #{scope.fetch('section_ids').join(', ')} · #{scope.fetch('target_ids').join(', ')}"],
      ["BLOCKING EFFECT", card.fetch("blocking_effect")],
      ["DECISION EPOCH", card.fetch("decision_epoch")],
      ["DISPATCH", card.fetch("dispatch_id")],
      ["RETURNED OUTPUT", "#{card.dig('returned_output', 'path')} · #{card.dig('returned_output', 'sha256')}"],
      ["DIRECTOR REVIEW", "#{card.dig('director_review', 'path')} · #{card.dig('director_review', 'row')}"],
      ["WORKER EVIDENCE", "#{worker_evidence.fetch('applicability')} · lineage #{worker_evidence.fetch('lineage_id')} · attempt #{worker_evidence.fetch('attempt_id')} · session #{worker_evidence['session_id'] || 'none'} · dispatch index #{dispatch_index.fetch('path')} · #{dispatch_index.fetch('row')} · #{dispatch_index.fetch('pointer')}"],
      ["FOUNDER LINEAGE", ["founder_receipt", "decision_export", "decision_intake"].map { |key| "#{key}: #{lineage.dig(key, 'path')}" }.join(" · ")]
    ]
    body = rows.map { |label, value| %(<dt>#{h(label)}</dt><dd class="mono">#{text_html(value)}</dd>) }.join
    %(<details class="field-refs decision-contract"><summary>Decision contract · #{h(section.fetch('cycle_kind'))}</summary><dl class="fact-list">#{body}</dl></details>)
  end

  def render_decision_buttons(card_id, review_key, section_id, scope_mode, affected_section_ids, stage_id, revision_id, decision_scope, revision_scope, review_target, review_mode, review_phase)
    affected = affected_section_ids.join(",")
    @manifest.fetch("decision_options").map do |option|
      %(<button type="button" class="decision tone-#{h(option.fetch('tone'))}" aria-pressed="false" data-review-key="#{h(review_key)}" data-review-mode="#{h(review_mode)}" data-review-phase="#{h(review_phase)}" data-review-card="#{h(card_id)}" data-review-section="#{h(section_id)}" data-review-scope-mode="#{h(scope_mode)}" data-review-affected-sections="#{h(affected)}" data-review-stage="#{h(stage_id)}" data-review-revision="#{h(revision_id)}" data-review-scope="#{h(decision_scope)}" data-revision-scope="#{h(revision_scope)}" data-review-target="#{h(review_target.fetch('target_id'))}" data-review-level="#{h(review_target.fetch('level'))}" data-review-number="#{h(review_target.fetch('display_number'))}" data-review-planning-cut="#{h(review_target['planning_cut_id'])}" data-review-core-cut="#{h(review_target['core_cut_id'])}" data-review-branch-cut="#{h(review_target['branch_cut_id'])}" data-review-choice="#{h(option.fetch('id'))}">#{h(option.fetch('label'))}</button>)
    end.join
  end

  def review_prompt_label(review_mode)
    {
      "g00_direction_draft" => "G-00 DIRECTION DRAFT",
      "g10_song_lock" => "G-10 SONG LOCK",
      "g20_visual_identity_lock" => "G-20 VISUAL IDENTITY LOCK",
      "g30_fp_final" => "G-30 FP FINAL",
      "g30_experiment_disposition" => "G-30 EXPERIMENT DISPOSITION",
      "g40_core_branch_authorization" => "G-40 CORE / BRANCH AUTHORIZATION",
      "g50_branch_results" => "G-50 BRANCH RESULTS",
      "video_playback_internal" => "CDD INTERNAL 03V PLAYBACK",
      "g60_playback_edit" => "G-60 PLAYBACK / EDIT",
      "g70_release" => "G-70 RELEASE"
    }.fetch(review_mode)
  end

  def render_mode_inputs(review_key, review_mode)
    extra = case review_mode
            when "g00_direction_draft"
              %(<label class="decision-note">Related card IDs for CONNECT THESE / KEEP ONLY<textarea rows="2" data-review-list="#{h(review_key)}" data-review-list-field="related_card_ids" placeholder="CARD-A, CARD-B"></textarea></label>)
            when "g30_fp_final"
              %(<p class="decision-locked">SELECT COMPLETE ROUTE chooses exactly one of FP-A, FP-B, or FP-C. It never performs an automatic merge.</p>)
            else
              ""
            end
    placeholder = %w[g40_core_branch_authorization g50_branch_results video_playback_internal g60_playback_edit g70_release].include?(review_mode) ? "For HOLD or REJECT, state what must change at this numbered target." : "Add the reason, search request, or direct comment. This does not create an unnamed lock."
    %(#{extra}<label class="decision-note">Decision note / targeted annotation<textarea rows="3" data-review-note="#{h(review_key)}" placeholder="#{h(placeholder)}"></textarea></label>)
  end

  def render_branch_cut_nav(sections)
    return "" unless @hierarchical_workbench

    links = sections.flat_map do |section|
      cycle_id = section.fetch("cycle_id")
      section.fetch("cards").map do |card|
        target = card.fetch("review_target")
        next unless target.fetch("level") == "branch_cut"

        label = "#{target.fetch('core_cut_id')}/#{target.fetch('branch_cut_id')} · #{resolve_text(card.fetch('title'), "#{card.fetch('card_id')}.title")}"
        %(<a href="##{h(cycle_id)}--#{h(card.fetch('card_id'))}">#{h(label)}</a>)
      end.compact
    end
    return "" if links.empty?

    %(<nav class="branch-cut-nav" aria-label="Branch Cut navigation"><span>BRANCH CUTS</span>#{links.join}</nav>)
  end

  def review_scope_label(section)
    return section.fetch("section_id") unless @workbench

    covered = section.fetch("covered_section_ids")
    case section.fetch("scope_mode")
    when "sectionless"
      section.fetch("review_mode").tr("_", " ").upcase
    when "single_section"
      covered.first
    when "multi_section"
      "Multiple sections (#{covered.length}) · #{covered.join(', ')}"
    when "whole_film"
      "Whole film (#{covered.length})"
    end
  end

  def affected_section_label(section_ids, scope_mode)
    return "No section lock" if scope_mode == "sectionless"
    return "Whole film · #{section_ids.length} sections" if scope_mode == "whole_film" && section_ids.length > 1

    section_ids.join(" · ")
  end

  def render_notices(notices)
    return "" if notices.empty?
    %(<div class="notices">#{notices.map { |notice| %(<div class="notice tone-#{h(notice.fetch('tone'))}">#{text_html(resolve_text(notice.fetch('text'), 'board.notice'))}</div>) }.join}</div>)
  end

  def render_sources
    @source_rows.values.map do |row|
      path = checked_repo_path(row.fetch("path"), "source.path", type: :file)
      href = path.relative_path_from(@output_path.dirname).to_s
      %(<a href="#{h(href)}"><strong>#{h(row.fetch('source_id'))}</strong><span>#{h(row.fetch('role'))}</span><code>#{h(row.fetch('path'))}<br>#{h(row.fetch('sha256'))}</code></a>)
    end.join
  end

  def stylesheet
    shell_asset_bytes("board-shell.css")
  end

  def lightbox_script
    shell_asset_bytes("board-lightbox.js")
  end

  def shell_asset_sha(name)
    Digest::SHA256.hexdigest(shell_asset_bytes(name))
  end

  def shell_asset_path(name)
    checked_repo_path("#{SHELL_ROOT}/#{name}", "review board shell #{name}", type: :file)
  end

  def load_document(path, label)
    raw = read_bound_bytes!(path, label).force_encoding(Encoding::UTF_8)
    case path.extname.downcase
    when ".json"
      JSON.parse(raw)
    when ".yaml", ".yml"
      YAML.safe_load(raw, permitted_classes: [Date, Time], aliases: true)
    else
      raise ReviewBoardContractError, "#{label} must be JSON or YAML: #{relative_to_repo(path)}"
    end
  rescue JSON::ParserError, Psych::Exception => e
    raise ReviewBoardContractError, "cannot parse #{label}: #{e.message}"
  end

  def file_identity(stat)
    [stat.dev, stat.ino]
  end

  def guard_input_file!(path, label)
    raise ReviewBoardContractError, "#{label} escapes repository root" unless inside?(path, @repo_root)
    reject_symlink_components!(path, label)
    raise ReviewBoardContractError, "#{label} is not a regular file" unless path.lstat.file?
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise ReviewBoardContractError, "#{label} file does not exist: #{relative_to_repo(path)}"
  end

  def remember_input!(path, sha256, label)
    prior = @bound_inputs[path.to_s]
    if prior && prior.fetch(:sha256) != sha256
      raise ReviewBoardContractError, "#{label} changed during validation"
    end
    @bound_inputs[path.to_s] ||= {path: path, sha256: sha256, label: label}
    sha256
  end

  def checked_file_read(path, label, retain_bytes:)
    guard_input_file!(path, label)
    bytes = retain_bytes ? +"".b : nil
    digest = Digest::SHA256.new
    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
      before = file.stat
      raise ReviewBoardContractError, "#{label} is not a regular file" unless before.file?
      while (chunk = file.read(1024 * 1024))
        digest.update(chunk)
        bytes << chunk if bytes
      end
      after = file.stat
      current = path.lstat
      unless file_identity(before) == file_identity(current) && !current.symlink? &&
             before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime
        raise ReviewBoardContractError, "#{label} changed while being read"
      end
    end
    guard_input_file!(path, label)
    [bytes, digest.hexdigest]
  rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
    raise ReviewBoardContractError, "#{label} path changed while being read"
  end

  def read_bound_bytes!(path, label)
    bytes, sha256 = checked_file_read(path, label, retain_bytes: true)
    remember_input!(path, sha256, label)
    bytes
  end

  def bind_file_hash!(path, label)
    _bytes, sha256 = checked_file_read(path, label, retain_bytes: false)
    remember_input!(path, sha256, label)
  end

  def recheck_bound_inputs!
    @bound_inputs.each_value do |entry|
      _bytes, actual = checked_file_read(entry.fetch(:path), entry.fetch(:label), retain_bytes: false)
      unless actual == entry.fetch(:sha256)
        raise ReviewBoardContractError, "#{entry.fetch(:label)} changed before publish"
      end
    end
  end

  def shell_asset_bytes(name)
    @shell_bytes[name] ||= read_bound_bytes!(shell_asset_path(name), "review board shell #{name}").force_encoding(Encoding::UTF_8)
  end

  def guard_output_route!
    raise ReviewBoardContractError, "output path escapes repository root" unless inside?(@output_path, @repo_root)
    reject_symlink_components!(@output_path, "output path")
    unless @output_path.dirname.directory?
      raise ReviewBoardContractError, "output parent directory disappeared"
    end
  end

  def output_snapshot!
    guard_output_route!
    return {exists: false} unless @output_path.exist?
    stat = @output_path.lstat
    raise ReviewBoardContractError, "output is not a regular file" unless stat.file?
    raise ReviewBoardContractError, "refusing hardlinked output" unless stat.nlink == 1
    bytes, sha256 = checked_file_read(@output_path, "output", retain_bytes: true)
    unless READABLE_GENERATOR_IDS.any? { |id| bytes.byteslice(0, 4096).to_s.include?(%(name="idol-generator" content="#{id}")) }
      raise ReviewBoardContractError, "refusing to replace non-generated HTML: #{relative_to_repo(@output_path)}"
    end
    {exists: true, identity: file_identity(stat), sha256: sha256}
  end

  def verify_output_snapshot!
    unless output_snapshot! == @expected_output
      raise ReviewBoardContractError, "generated output changed before publish"
    end
  end

  def verify_lock_identity!(lock, lock_path)
    reject_symlink_components!(lock_path, "output lock")
    path_stat = lock_path.lstat
    unless path_stat.file? && lock.stat.file? && file_identity(path_stat) == file_identity(lock.stat)
      raise ReviewBoardContractError, "output lock path changed during acquisition"
    end
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise ReviewBoardContractError, "output lock path disappeared"
  end

  def allocate_output_temp!
    guard_output_route!
    128.times do |nonce|
      path = @output_path.dirname.join(".#{@output_path.basename}.tmp-#{Process.pid}-#{nonce}")
      begin
        file = File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o644)
        file.binmode
        return [path, file]
      rescue Errno::EEXIST
        next
      end
    end
    raise ReviewBoardContractError, "cannot allocate an exclusive output temporary file"
  end

  def checked_repo_path(text, label, type:)
    raise ReviewBoardContractError, "#{label} must be repository-relative" if Pathname.new(text).absolute?
    raise ReviewBoardContractError, "#{label} must not be a URL" if text.match?(/\A[a-z][a-z0-9+.-]*:/i)
    path = @repo_root.join(text).cleanpath
    raise ReviewBoardContractError, "#{label} escapes repository root" unless inside?(path, @repo_root)
    reject_symlink_components!(path, label)
    case type
    when :file
      raise ReviewBoardContractError, "#{label} file does not exist: #{text}" unless path.file?
    when :directory
      raise ReviewBoardContractError, "#{label} directory does not exist: #{text}" unless path.directory?
    when :output
      raise ReviewBoardContractError, "#{label} parent directory escapes repository" unless inside?(path.dirname, @repo_root)
    end
    path
  end

  def reject_symlink_components!(path, label)
    relative = path.relative_path_from(@repo_root)
    cursor = @repo_root
    relative.each_filename do |part|
      cursor = cursor.join(part)
      break unless cursor.exist? || cursor.symlink?
      raise ReviewBoardContractError, "#{label} crosses a symlink: #{relative_to_repo(cursor)}" if cursor.symlink?
    end
  end

  def inside?(path, root)
    path_text = path.expand_path.cleanpath.to_s
    root_text = root.expand_path.cleanpath.to_s
    path_text == root_text || path_text.start_with?(root_text + File::SEPARATOR)
  end

  def relative_to_repo(path)
    Pathname.new(path).expand_path.cleanpath.relative_path_from(@repo_root).to_s
  rescue ArgumentError
    path.to_s
  end

  def expect_hash(value, label)
    raise ReviewBoardContractError, "#{label} must be an object" unless value.is_a?(Hash)
    value
  end

  def expect_array(value, label, minimum: 0)
    raise ReviewBoardContractError, "#{label} must be an array" unless value.is_a?(Array)
    raise ReviewBoardContractError, "#{label} must contain at least #{minimum} item(s)" if value.length < minimum
    value
  end

  def expect_keys(value, required, allowed, label)
    missing = required - value.keys
    unknown = value.keys - allowed
    raise ReviewBoardContractError, "#{label} missing required keys: #{missing.join(', ')}" unless missing.empty?
    raise ReviewBoardContractError, "#{label} has unknown keys: #{unknown.join(', ')}" unless unknown.empty?
  end

  def expect_string(value, label)
    raise ReviewBoardContractError, "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
    value
  end

  def expect_id(value, label)
    text = expect_string(value, label)
    raise ReviewBoardContractError, "#{label} has invalid id syntax" unless text.match?(ID_RE)
    text
  end

  def expect_sha(value, label)
    text = expect_string(value, label)
    raise ReviewBoardContractError, "#{label} must be lowercase SHA-256" unless text.match?(SHA_RE)
    text
  end

  def expect_member(value, allowed, label)
    raise ReviewBoardContractError, "#{label} must be one of: #{allowed.join(', ')}" unless allowed.include?(value)
    value
  end

  def expect_equal(value, expected, label)
    raise ReviewBoardContractError, "#{label} must equal #{expected}" unless value == expected
    value
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  def text_html(value)
    h(value).gsub("\n", "<br>")
  end
end

options = {
  repo_root: Pathname.new(__dir__).parent.to_s,
  json: false
}

parser = OptionParser.new do |opts|
  opts.banner = <<~USAGE
    usage:
      ruby scripts/idol_html_review_board.rb validate MANIFEST [--repo-root PATH] [--json]
      ruby scripts/idol_html_review_board.rb render MANIFEST [--repo-root PATH] [--json]
  USAGE
  opts.on("--repo-root PATH", "Repository root. Defaults to the parent of scripts/.") { |value| options[:repo_root] = value }
  opts.on("--json", "Print machine-readable result.") { options[:json] = true }
end

command = ARGV.shift
manifest_path = ARGV.shift
parser.parse!(ARGV)

unless %w[validate render].include?(command) && manifest_path
  warn parser.to_s
  exit 2
end

begin
  renderer = IdolHtmlReviewBoard.new(manifest_path, repo_root: options[:repo_root])
  result = if command == "render"
    renderer.write!
  else
    {
      "status" => "valid",
      "manifest_path" => renderer.manifest_path.relative_path_from(renderer.repo_root).to_s,
      "manifest_sha256" => renderer.manifest_sha256,
      "output_path" => renderer.output_path.relative_path_from(renderer.repo_root).to_s
    }
  end
  puts(options[:json] ? JSON.pretty_generate(result) : result.map { |key, value| "#{key}: #{value}" }.join("\n"))
rescue ReviewBoardContractError => e
  warn(options[:json] ? JSON.generate({"status" => "invalid", "error" => e.message}) : "ERROR: #{e.message}")
  exit 1
end
