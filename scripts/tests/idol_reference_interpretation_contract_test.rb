# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require "yaml"
require_relative "../lib/idol_reference_interpretation_contract"

class IdolReferenceInterpretationContractTest < Minitest::Test
  def setup
    @root = Pathname.new(Dir.mktmpdir("idol-reference-interpretation-"))
    @owner_path = @root.join("runs/2026-07-12/REFERENCE_TEST/research/front-planning-readiness-v2.yaml")
    @owner_path.dirname.mkpath
    @sheet_path = @root.join("assets/reference/contact-sheet.png")
    @image_path = @root.join("assets/reference/contact-sheet-selected-cell.png")
    @image_path.dirname.mkpath
    @sheet_path.binwrite("full contact sheet pixels")
    @image_path.binwrite("selected reference cell pixels")
    @owner = owner_document
    @owner_path.write(YAML.dump(@owner))
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.directory?
  end

  def test_owner_receipt_binds_observation_locator_function_and_inspected_pixels
    assert_empty IdolReferenceInterpretationContract.validate_owner_document(@owner_path, @owner, root: @root)

    drifted = Marshal.load(Marshal.dump(@owner))
    drifted.dig("section_work_plan", "sections", 0, "downstream_01_transfer")["function_extracted"] = "A different later-session reading."
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, drifted, root: @root)
    assert errors.any? { |error| error.include?("value_sha256 is stale") }
  end

  def test_selected_contact_sheet_receipt_cannot_omit_selected_cells
    broken = Marshal.load(Marshal.dump(@owner))
    broken.dig("interpretation_contract", "reference_interpretation_index", 0, "inspected_sources", 0)["selected_cells_or_frames"] = []
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, broken, root: @root)
    assert errors.any? { |error| error.include?("selected_cells_or_frames is required") }
  end

  def test_selected_function_cannot_be_a_media_kind
    broken = Marshal.load(Marshal.dump(@owner))
    pointer = "/section_work_plan/sections/0/downstream_01_transfer/function_extracted"
    broken.dig("section_work_plan", "sections", 0, "downstream_01_transfer")["function_extracted"] = "video"
    selected = broken.dig("interpretation_contract", "reference_interpretation_index", 0, "components").find do |row|
      row["role"] == "selected_function"
    end
    selected["value_sha256"] = IdolReferenceInterpretationContract.canonical_digest(
      IdolReferenceInterpretationContract.pointer_value(broken, pointer)
    )

    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, broken, root: @root)

    assert errors.any? { |error| error.include?("screen function, not a media kind") }
  end

  def test_selected_contact_sheet_receipt_requires_hash_bound_derivative_not_whole_sheet
    missing = Marshal.load(Marshal.dump(@owner))
    missing.dig("interpretation_contract", "reference_interpretation_index", 0, "inspected_sources", 0).delete("selected_surface_artifacts")
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, missing, root: @root)
    assert errors.any? { |error| error.include?("selected_surface_artifacts must carry") }

    whole_sheet = Marshal.load(Marshal.dump(@owner))
    derivative = whole_sheet.dig("interpretation_contract", "reference_interpretation_index", 0, "inspected_sources", 0, "selected_surface_artifacts", 0)
    derivative["path"] = @sheet_path.relative_path_from(@root).to_s
    derivative["sha256"] = Digest::SHA256.file(@sheet_path.to_s).hexdigest
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, whole_sheet, root: @root)
    assert errors.any? { |error| error.include?("not the whole sheet/board source") }
  end

  def test_selected_contact_sheet_derivative_must_bind_its_exact_parent_source
    broken = Marshal.load(Marshal.dump(@owner))
    derivative = broken.dig("interpretation_contract", "reference_interpretation_index", 0, "inspected_sources", 0, "selected_surface_artifacts", 0)
    derivative["source_path"] = @image_path.relative_path_from(@root).to_s
    derivative["source_sha256"] = Digest::SHA256.file(@image_path.to_s).hexdigest
    derivative["derivation_kind"] = "board_cell_crop"

    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, broken, root: @root)
    assert errors.any? { |error| error.include?("source_path must match the inspected source") }
    assert errors.any? { |error| error.include?("source_sha256 must match the inspected source") }
    assert errors.any? { |error| error.include?("derivation_kind must be contact_sheet_cell_crop") }
  end

  def test_selected_01r_and_v2_fragment_rows_cannot_handoff_without_receipts
    selected_01r = {
      "reference_captures" => [{"reference_id" => "01R-TEST", "capture_status" => "selected_for_01"}]
    }
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, selected_01r, root: @root)
    assert errors.any? { |error| error.include?("selected_for_01 requires interpretation_receipt") }

    selected_fragment = {
      "schema_version" => "idol_reference_fragment_crop_lock.v2",
      "fragments" => [{"fragment_id" => "FRAG_TEST", "status" => "selected"}],
      "section_fragment_map" => []
    }
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, selected_fragment, root: @root)
    assert errors.any? { |error| error.include?("selected/ready v2 fragment requires interpretation_receipt") }
  end

  def test_legacy_01_without_advertised_contract_remains_readable_but_resumed_contract_holds
    legacy_source = @root.join("runs/2026-07-12/REFERENCE_TEST/research/legacy-reference.yaml")
    legacy_source.write(YAML.dump("reference_captures" => [{"reference_id" => "01R-LEGACY"}]))
    direction_path = @root.join("runs/2026-07-12/REFERENCE_TEST/01-legacy.yaml")
    direction = {
      "research_synthesis" => {
        "source_artifacts" => [{
          "source_id" => "SRC_LEGACY",
          "path" => legacy_source.relative_path_from(@root).to_s,
          "artifact_sha256" => Digest::SHA256.file(legacy_source.to_s).hexdigest
        }],
        "selected_application_index" => [{"application_id" => "APP_LEGACY"}]
      }
    }
    assert_empty IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, direction, root: @root)

    direction["research_synthesis"]["interpretation_binding_contract"] = IdolReferenceInterpretationContract::INTERPRETATION_BINDING_CONTRACT
    errors = IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, direction, root: @root)
    assert errors.any? { |error| error.include?("missing interpretation_bindings") }
  end

  def test_revision_two_requires_approved_trigger_parent_and_downstream_invalidation
    broken = Marshal.load(Marshal.dump(@owner))
    revision = broken.dig("interpretation_contract", "reference_interpretation_index", 0, "revision")
    revision["number"] = 2
    revision["reopen_trigger"] = "new_session_new_opinion"
    revision["previous_receipt_sha256"] = nil
    revision["invalidates_from_stage"] = "none"
    errors = IdolReferenceInterpretationContract.validate_owner_document(@owner_path, broken, root: @root)
    assert errors.any? { |error| error.include?("unapproved reopen trigger") }
    assert errors.any? { |error| error.include?("requires previous_receipt_sha256") }
    assert errors.any? { |error| error.include?("invalidate affected downstream") }
  end

  def test_01_binding_consumes_exact_upstream_receipt_without_reinterpretation
    receipt = @owner.dig("interpretation_contract", "reference_interpretation_index", 0)
    direction_path = @root.join("runs/2026-07-12/REFERENCE_TEST/01-song-choreography-performance-mv-map.yaml")
    direction = direction_document(receipt)
    direction_path.write(YAML.dump(direction))

    assert_empty IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, direction, root: @root)

    drifted = Marshal.load(Marshal.dump(direction))
    drifted.dig("research_synthesis", "selected_application_index", 0)["selected_function"] = "A later model invents a new reading."
    errors = IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, drifted, root: @root)
    assert errors.any? { |error| error.include?("reinterprets its exact bound receipt") }

    stale = Marshal.load(Marshal.dump(direction))
    stale.dig("research_synthesis", "selected_application_index", 0, "interpretation_bindings", 0)["source_receipt_sha256"] = "0" * 64
    errors = IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, stale, root: @root)
    assert errors.any? { |error| error.include?("source_receipt_sha256 is stale") }
  end

  def test_source_byte_change_invalidates_01_binding
    receipt = @owner.dig("interpretation_contract", "reference_interpretation_index", 0)
    direction_path = @root.join("runs/2026-07-12/REFERENCE_TEST/01-song-choreography-performance-mv-map.yaml")
    direction = direction_document(receipt)
    @owner_path.write(@owner_path.read + "\n# upstream mutation\n")

    errors = IdolReferenceInterpretationContract.validate_direction_bindings(direction_path, direction, root: @root)
    assert errors.any? { |error| error.include?("source artifact_sha256 is stale") }
  end

  private

  def owner_document
    document = {
      "schema_version" => "front-planning-readiness.v2",
      "section_work_plan" => {
        "sections" => [
          {
            "section_id" => "S04",
            "reference_observation" => {
              "visible_fact" => "The reflected grid closes behind the foreground stone only in the selected cell."
            },
            "selected_cell" => {
              "sheet_part" => "part-02",
              "cell_id" => "cell-07",
              "source_timecode" => "00:42.0"
            },
            "downstream_01_transfer" => {
              "function_extracted" => "Close the reflected grid exactly when the foreground stone lands."
            }
          }
        ]
      },
      "interpretation_contract" => {
        "reference_interpretation_index" => []
      }
    }
    pointers = {
      "source_observation" => "/section_work_plan/sections/0/reference_observation",
      "evidence_locator" => "/section_work_plan/sections/0/selected_cell",
      "selected_function" => "/section_work_plan/sections/0/downstream_01_transfer/function_extracted"
    }
    receipt = {
      "interpretation_id" => "RINT_GRID_CLOSURE",
      "component_owner" => {"mode" => "self"},
      "components" => pointers.map do |role, pointer|
        {"role" => role, "json_pointer" => pointer, "value_sha256" => IdolReferenceInterpretationContract.canonical_digest(IdolReferenceInterpretationContract.pointer_value(document, pointer))}
      end,
      "inspected_sources" => [
        {
          "path" => @sheet_path.relative_path_from(@root).to_s,
          "sha256" => Digest::SHA256.file(@sheet_path.to_s).hexdigest,
          "media_kind" => "contact_sheet",
          "inspection_scope" => "selected_sheet_cells",
          "selected_cells_or_frames" => ["part-02/cell-07@00:42.0"],
          "selected_surface_artifacts" => [{
            "surface_id" => "part-02/cell-07@00:42.0",
            "path" => @image_path.relative_path_from(@root).to_s,
            "sha256" => Digest::SHA256.file(@image_path.to_s).hexdigest,
            "source_path" => @sheet_path.relative_path_from(@root).to_s,
            "source_sha256" => Digest::SHA256.file(@sheet_path.to_s).hexdigest,
            "derivation_kind" => "contact_sheet_cell_crop"
          }]
        }
      ],
      "revision" => {
        "number" => 1,
        "reopen_trigger" => "initial_analysis",
        "previous_receipt_sha256" => nil,
        "invalidates_from_stage" => "none",
        "reason" => "Initial Front Planning interpretation of the Founder-supplied reference cell."
      },
      "disposition" => "applied",
      "target_section_ids" => ["S04"],
      "target_scopes" => ["section"],
      "consume_mode" => "consume_bound_interpretation_without_source_reread"
    }
    document.dig("interpretation_contract", "reference_interpretation_index") << receipt
    document
  end

  def direction_document(receipt)
    {
      "research_synthesis" => {
        "interpretation_binding_contract" => IdolReferenceInterpretationContract::INTERPRETATION_BINDING_CONTRACT,
        "source_artifacts" => [
          {
            "source_id" => "SRC_FRONT_PLANNING",
            "source_type" => "front_planning",
            "path" => @owner_path.relative_path_from(@root).to_s,
            "artifact_sha256" => Digest::SHA256.file(@owner_path.to_s).hexdigest
          }
        ],
        "selected_application_index" => [
          {
            "application_id" => "APP_GRID_CLOSURE",
            "source_identities" => ["Founder grid-closure reference"],
            "selected_function" => "Close the reflected grid exactly when the foreground stone lands.",
            "target_section_ids" => ["S04"],
            "interpretation_bindings" => [
              {
                "receipt_id" => "RINT_GRID_CLOSURE",
                "source_id" => "SRC_FRONT_PLANNING",
                "source_receipt_json_pointer" => "/interpretation_contract/reference_interpretation_index/0",
                "source_receipt_sha256" => IdolReferenceInterpretationContract.canonical_digest(receipt),
                "source_revision" => 1,
                "binding_mode" => "exact",
                "consume_mode" => "consume_bound_interpretation_without_source_reread"
              }
            ]
          }
        ]
      }
    }
  end
end
