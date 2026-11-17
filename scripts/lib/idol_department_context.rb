# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "securerandom"
require "tempfile"
require "time"
require "yaml"
require_relative "idol_role_context_pack"

module IdolDepartmentContext
  class ContractError < StandardError; end

  IMPLEMENTATION_ROOT = Pathname.new(__dir__).join("..", "..").expand_path.cleanpath
  SCHEMA_RELATIVE = "schemas/department-runtime-context.schema.json"
  DISPATCH_SCHEMA_RELATIVE = "schemas/department-dispatch.schema.json"
  DISPATCH_VALIDATOR_RELATIVE = "scripts/validate_department_dispatch.rb"
  JSON_SCHEMA_VALIDATOR_RELATIVE = "scripts/validate_json_schema.py"
  SCHEMA_VERSION = "idol-department-runtime-context.v1"
  AUTHORITY = "transport_context_no_creative_or_promotion_authority"
  RECEIPT_SCHEMA_VERSION = "idol-department-context-application.v1"
  INSTRUCTION_DELIVERY = "role_context_pack"
  REQUIRED_PROVIDER = "grok"
  REQUIRED_MODEL = "grok-4.6"
  REQUIRED_EFFORT = "xhigh"
  REQUIRED_RUNTIME_SURFACE = "grok_build_cli_acp"
  REQUIRED_EVIDENCE_SOURCE = "grok_acp_goal_updated_event"
  DISPATCH_SCHEMA_VERSION = "idol-department-dispatch.v8"
  GRAPH_DISPATCH_SCHEMA = "idol-graph-department-dispatch.v1"
  MAX_INPUT_BYTES = 2 * 1024 * 1024
  MAX_DISPATCH_BYTES = 2 * 1024 * 1024
  MAX_ERROR_BYTES = 4_096
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/
  ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{2,120}\z/
  GOAL_BINDING_FIELDS = %w[
    provider
    native_goal_id
    native_session_id
    assignment_key
    dispatch_id
    attempt_id
    runtime_surface
    goal_text_sha256
    raw_event_sha256
    observed_at
    evidence_source
    objective
    request_id
  ].freeze
  ADAPTER_GOAL_FIELDS = %w[state command turn_id provider_prompt_id].freeze
  RECEIPT_FIELDS = %w[
    schema_version
    context_packet
    dispatch_id
    attempt_id
    dispatch_input_sha256
    native_goal_id
    native_session_id
    native_goal_raw_event_sha256
    pack_id
    pack_digest
    source_set_sha256
    instruction_content_sha256
    applied_at
  ].freeze
  CONTEXT_FIELDS = %w[
    schema_version
    authority
    dispatch_id
    run
    attempt_id
    dispatch_input_sha256
    source_dispatch
    goal_binding
    prepared_at
    role_context_pack
    worker_prompt
    worker_prompt_sha256
  ].freeze
  POINTER_FIELDS = %w[path sha256].freeze
  PREPARE_INPUT_FIELDS = %w[action dispatch_path dispatch_sha256 runtime_goal].freeze
  VALIDATE_INPUT_FIELDS = %w[action dispatch_path dispatch_sha256 runtime_goal application work_started_at returned_at].freeze
  INSTRUCTION_DELIVERY_DIRECTIVE = <<~TEXT.chomp
    [Instruction delivery: role_context_pack]
    The deterministic projector verified the registered source closure. Apply the exact Role Context Pack below and inspect the named current creative sources. The broad skill list is an invalidation inventory, not a second required read. Do not claim full-source EOF from a fragment. Keep the original task, creative meaning, scope, authority and return recipient. In the final fp_department_return, use skill_revisions: [] and role_context_receipt with the exact transport receipt fields and your actual applied_at timestamp before work_started_at. Pack application is not creative PASS.
  TEXT
  SCHEMA_REF_ADAPTER_PYTHON = <<~'PY'
    import importlib.util
    import json
    import os
    import sys
    from pathlib import Path
    from urllib.parse import urldefrag, urlparse

    validator_py = Path(sys.argv[1])
    schema_path = Path(os.path.abspath(os.path.normpath(sys.argv[2])))
    instance_path = Path(os.path.abspath(os.path.normpath(sys.argv[3])))
    schemas_dir = Path(os.path.abspath(os.path.normpath(sys.argv[4])))

    spec = importlib.util.spec_from_file_location("idol_validate_json_schema", str(validator_py))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    import jsonschema
    from referencing import Registry, Resource

    def contained(path):
        path_s = os.path.abspath(os.path.normpath(str(path)))
        root_s = os.path.abspath(os.path.normpath(str(schemas_dir)))
        try:
            return os.path.commonpath([root_s, path_s]) == root_s
        except ValueError:
            return False

    def reject_link(path, label):
        if path.is_symlink():
            raise SystemExit(f"{label} must not be a symlink: {path}")

    def local_schema_file(uri, base_path):
        uri, _frag = urldefrag(uri)
        if not uri:
            return None
        parsed = urlparse(uri)
        if parsed.scheme in ("http", "https"):
            if parsed.netloc != "aheyabaraya.local":
                raise SystemExit(f"unknown schema id rejected without network: {uri}")
            name = Path(parsed.path).name
            if name == "" or "/" in name or name != Path(parsed.path).name:
                raise SystemExit(f"unknown schema id rejected without network: {uri}")
            candidate = Path(os.path.abspath(os.path.normpath(str(schemas_dir / name))))
        elif parsed.scheme in ("",):
            candidate = Path(os.path.abspath(os.path.normpath(str(base_path.parent / uri))))
        else:
            raise SystemExit(f"unknown schema id rejected without network: {uri}")
        if not contained(candidate):
            raise SystemExit(f"schema reference escapes schemas directory: {uri}")
        reject_link(candidate, "schema file")
        if not candidate.is_file():
            raise SystemExit(f"unknown schema id rejected without network: {uri}")
        return candidate

    def collect_refs(node, acc):
        if isinstance(node, dict):
            ref = node.get("$ref")
            if isinstance(ref, str):
                acc.append(ref)
            for value in node.values():
                collect_refs(value, acc)
        elif isinstance(node, list):
            for value in node:
                collect_refs(value, acc)

    reject_link(schema_path, "schema file")
    if not contained(schema_path):
        raise SystemExit(f"schema path escapes schemas directory: {schema_path}")

    loaded = {}
    queue = [schema_path]
    resources = []
    while queue:
        path = queue.pop()
        key = str(path)
        if key in loaded:
            continue
        reject_link(path, "schema file")
        if not contained(path):
            raise SystemExit(f"schema path escapes schemas directory: {path}")
        data = mod.load_document(path)
        loaded[key] = data
        resource = Resource.from_contents(data)
        resources.append((path.name, resource))
        ident = data.get("$id") if isinstance(data, dict) else None
        if ident:
            resources.append((ident, resource))
        refs = []
        collect_refs(data, refs)
        for ref in refs:
            nxt = local_schema_file(ref, path)
            if nxt is not None and str(nxt) not in loaded:
                queue.append(nxt)

    registry = Registry().with_resources(resources)
    schema = loaded[str(schema_path)]
    instance = mod.load_document(instance_path)
    validator_cls = jsonschema.validators.validator_for(schema)
    validator = validator_cls(schema, registry=registry, format_checker=jsonschema.FormatChecker())
    errors = sorted(validator.iter_errors(instance), key=lambda err: list(err.absolute_path))
    if errors:
        messages = []
        for error in errors[:20]:
            loc = "$" if not error.absolute_path else "$." + ".".join(str(part) for part in error.absolute_path)
            messages.append(f"{loc}: {error.message}")
        sys.stderr.write("schema validation failed: " + "; ".join(messages) + "\n")
        sys.exit(1)
    print("schema ok")
  PY

  SelectedInput = Struct.new(
    :root,
    :path,
    :relative,
    :bytes,
    :sha256,
    :dev,
    :ino,
    :nlink,
    :size,
    :ancestors,
    keyword_init: true
  )

  module_function

  def prepare(root:, dispatch_path:, dispatch_sha256:, runtime_goal:)
    raise ContractError, "File::NOFOLLOW is required" unless File.const_defined?(:NOFOLLOW)

    root = expand_root(root)
    selected = capture_selected_file!(root, dispatch_path, label: "launched dispatch")
    unless selected.sha256 == normalize_sha256!(dispatch_sha256, "dispatch_sha256")
      raise ContractError, "launched dispatch SHA-256 does not match the live file"
    end
    document = load_mapping_bytes(selected.bytes, selected.relative)
    assert_current_v8_launched_dispatch!(root, selected, document)
    recheck_selected_input!(selected, "launched dispatch after validation")
    goal_binding = normalize_goal_binding!(runtime_goal, document)
    assert_provider_and_writer!(document)
    input_digest = structured_sha256(
      "lineage" => document.fetch("lineage"),
      "review_submission" => document.fetch("review_submission"),
      "launch" => document.fetch("launch")
    )
    dispatch_id = document.fetch("dispatch_id").to_s
    attempt_id = document.fetch("lineage").fetch("attempt_id").to_s
    run = document.fetch("run").to_s
    snapshot_rel, context_rel = derived_context_paths(run, dispatch_id, attempt_id)
    context_dir = ensure_directory_chain!(root, Pathname.new(snapshot_rel).dirname.to_s, run: run)
    snapshot_path = context_dir.join(Pathname.new(snapshot_rel).basename)
    context_path = context_dir.join(Pathname.new(context_rel).basename)
    result = publish_or_reuse!(
      root: root,
      selected: selected,
      document: document,
      goal_binding: goal_binding,
      input_digest: input_digest,
      snapshot_path: snapshot_path,
      snapshot_relative: snapshot_rel,
      context_path: context_path,
      context_relative: context_rel
    )
    recheck_selected_input!(selected, "launched dispatch before returning the packet")
    result
  end

  def validate_application!(root:, dispatch:, runtime_goal:, application:, work_started_at:, returned_at:)
    raise ContractError, "File::NOFOLLOW is required" unless File.const_defined?(:NOFOLLOW)

    root = expand_root(root)
    document = if dispatch.is_a?(Hash)
                 dispatch
               else
                 selected = capture_selected_file!(root, dispatch, label: "department dispatch")
                 load_mapping_bytes(selected.bytes, selected.relative)
               end
    assert_v8_dispatch_identity!(document)
    receipt = normalize_receipt!(application)
    packet, packet_bytes, actual_sha, expected_snapshot, expected_context = load_validated_context_packet!(
      root: root,
      document: document,
      receipt: receipt
    )
    goal_input = runtime_goal.is_a?(Hash) ? runtime_goal.dup : runtime_goal
    goal_binding = normalize_goal_binding!(goal_input, document)
    unless canonical_value(packet.fetch("goal_binding")) == canonical_value(goal_binding)
      raise ContractError, "runtime Goal binding does not match the frozen context goal_binding"
    end
    snapshot_selected = capture_selected_file!(
      root,
      packet.fetch("source_dispatch").fetch("path"),
      label: "launched dispatch snapshot",
      run: document.fetch("run").to_s
    )
    unless snapshot_selected.sha256 == packet.fetch("source_dispatch").fetch("sha256")
      raise ContractError, "frozen launched dispatch snapshot SHA-256 is stale"
    end
    snapshot = load_mapping_bytes(snapshot_selected.bytes, snapshot_selected.relative)
    assert_immutable_launch_binding!(snapshot, document, packet.fetch("dispatch_input_sha256"))
    expected_pack = rebuild_expected_pack!(root, snapshot_selected.relative)
    unless canonical_value(packet.fetch("role_context_pack")) == canonical_value(expected_pack)
      raise ContractError, "frozen role_context_pack does not equal IdolRoleContextPack.build_from_dispatch on the launched snapshot"
    end
    expected_prompt = expected_worker_prompt(document, expected_pack)
    unless packet.fetch("worker_prompt").to_s == expected_prompt
      raise ContractError, "frozen worker_prompt is not original compiled prompt + root directive + render_runtime_json(exact pack)"
    end
    unless Digest::SHA256.hexdigest(expected_prompt) == packet["worker_prompt_sha256"].to_s
      raise ContractError, "worker_prompt_sha256 is stale"
    end
    pack_errors = IdolRoleContextPack.validate_pack(root: root, pack: expected_pack, validation_mode: "active_promotion")
    raise ContractError, "role context pack failed active_promotion validation: #{pack_errors.join('; ')}" unless pack_errors.empty?
    raise ContractError, "role context pack status is not pass" unless expected_pack["status"].to_s == "pass"
    assert_receipt_matches_packet!(receipt, packet, expected_pack, expected_context, actual_sha, goal_binding)
    assert_application_timeline!(
      observed_at: goal_binding.fetch("observed_at"),
      prepared_at: packet.fetch("prepared_at"),
      applied_at: receipt.fetch("applied_at"),
      work_started_at: work_started_at,
      returned_at: returned_at
    )
    true
  end

  def validate_owning_dispatch_schema!(root:, instance_path:)
    validate_owning_schema!(
      root: root,
      schema_relative: DISPATCH_SCHEMA_RELATIVE,
      instance_path: instance_path,
      label: "department dispatch"
    )
  end

  def validate_owning_schema!(root:, schema_relative:, instance_path:, label:)
    root = expand_root(root)
    schema_path = contained_regular_file!(root, schema_relative, label: "owning schema")
    instance = Pathname.new(instance_path.to_s)
    instance = instance.absolute? ? instance : root.join(instance)
    instance = instance.expand_path.cleanpath
    python = python_bin
    validator_py = IMPLEMENTATION_ROOT.join(JSON_SCHEMA_VALIDATOR_RELATIVE)
    raise ContractError, "validate_json_schema.py is missing" unless validator_py.file?
    stdout, stderr, status = Open3.capture3(
      python.to_s,
      "-c",
      SCHEMA_REF_ADAPTER_PYTHON,
      validator_py.to_s,
      schema_path.to_s,
      instance.to_s,
      root.join("schemas").to_s,
      chdir: root.to_s
    )
    return true if status.success?

    message = [stderr, stdout].reject { |value| value.to_s.strip.empty? }.join(" ").strip
    raise ContractError, "#{label} failed owning JSON Schema validation: #{truncate_error(message)}"
  end

  def prepare_from_cli_payload(payload, root:)
    reject_unknown_keys!(payload, PREPARE_INPUT_FIELDS, "prepare input")
    raise ContractError, "prepare action is required" unless payload["action"].to_s == "prepare"
    prepare(
      root: root,
      dispatch_path: payload["dispatch_path"],
      dispatch_sha256: payload["dispatch_sha256"],
      runtime_goal: payload["runtime_goal"]
    )
  end

  def validate_from_cli_payload(payload, root:)
    reject_unknown_keys!(payload, VALIDATE_INPUT_FIELDS, "validate input")
    raise ContractError, "validate action is required" unless payload["action"].to_s == "validate"
    selected = capture_selected_file!(expand_root(root), payload["dispatch_path"], label: "department dispatch")
    unless selected.sha256 == normalize_sha256!(payload["dispatch_sha256"], "dispatch_sha256")
      raise ContractError, "live dispatch SHA-256 does not match dispatch_sha256"
    end
    document = load_mapping_bytes(selected.bytes, selected.relative)
    validate_application!(
      root: root,
      dispatch: document,
      runtime_goal: payload["runtime_goal"],
      application: payload["application"],
      work_started_at: payload["work_started_at"],
      returned_at: payload["returned_at"]
    )
    recheck_selected_input!(selected, "department dispatch after validate")
    {"ok" => true}
  end

  def assignment_key_from_owner(owner)
    text = owner.to_s
    raise ContractError, "launch assigned_owner is missing" if text.empty?
    match = text.match(/\A(?:luna_)?department_worker:(.+)\z/)
    key = match ? match[1].to_s : text
    raise ContractError, "launch assigned_owner does not yield an assignment_key" if key.empty?
    key
  end

  def truncate_error(message)
    text = message.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
    return text if text.bytesize <= MAX_ERROR_BYTES

    text.byteslice(0, MAX_ERROR_BYTES).force_encoding("UTF-8").scrub + "…"
  end

  def expand_root(root)
    path = Pathname.new(root.to_s).expand_path.cleanpath
    raise ContractError, "root is missing" unless path.directory?
    st = File.lstat(path.to_s)
    raise ContractError, "root must be a directory" unless st.directory?
    path
  end

  def publish_or_reuse!(root:, selected:, document:, goal_binding:, input_digest:, snapshot_path:, snapshot_relative:, context_path:, context_relative:)
    lock_path = snapshot_path.dirname.join(".publish.lock")
    open_publish_lock!(lock_path) do
      recheck_selected_input!(selected, "launched dispatch at publish lock")
      snapshot_exists = path_exists_nofollow?(snapshot_path)
      context_exists = path_exists_nofollow?(context_path)
      if snapshot_exists || context_exists
        unless regular_file_one_link?(snapshot_path) && regular_file_one_link?(context_path)
          raise ContractError, "partial department context metadata exists and cannot be overwritten"
        end
        return reuse_immutable_context!(
          root: root,
          selected: selected,
          document: document,
          goal_binding: goal_binding,
          input_digest: input_digest,
          snapshot_path: snapshot_path,
          snapshot_relative: snapshot_relative,
          context_path: context_path,
          context_relative: context_relative
        )
      end
      exclusive_publish!(snapshot_path, selected.bytes)
      pack = rebuild_expected_pack!(root, snapshot_relative)
      prepared_at = Time.now.utc.iso8601(6)
      packet_bytes = render_context_bytes(
        document: document,
        goal_binding: goal_binding,
        input_digest: input_digest,
        snapshot_relative: snapshot_relative,
        snapshot_sha256: selected.sha256,
        prepared_at: prepared_at,
        pack: pack
      )
      if packet_bytes.bytesize > MAX_DISPATCH_BYTES
        raise ContractError, "department runtime context exceeds the bounded output size"
      end
      validate_rendered_context_bytes!(root, packet_bytes)
      recheck_selected_input!(selected, "launched dispatch before context publish")
      begin
        exclusive_publish!(context_path, packet_bytes)
      rescue StandardError
        raise ContractError, "department context JSON publish failed after snapshot evidence was preserved"
      end
      packet_result(context_relative, packet_bytes)
    end
  end

  def reuse_immutable_context!(root:, selected:, document:, goal_binding:, input_digest:, snapshot_path:, snapshot_relative:, context_path:, context_relative:)
    snapshot_bytes = read_nofollow_file_bytes!(snapshot_path, "launched dispatch snapshot")
    unless snapshot_bytes == selected.bytes
      raise ContractError, "existing launched dispatch snapshot does not match the current launched dispatch and cannot be overwritten"
    end
    packet_bytes = utf8_bytes!(read_nofollow_file_bytes!(context_path, "department runtime context"), "department runtime context")
    packet = JSON.parse(packet_bytes)
    raise ContractError, "existing department runtime context must be one JSON object" unless packet.is_a?(Hash)
    reject_unknown_keys!(packet, CONTEXT_FIELDS, "department runtime context")
    unless packet["dispatch_input_sha256"].to_s == input_digest
      raise ContractError, "existing context input digest does not match the current launched dispatch and cannot be overwritten"
    end
    unless canonical_value(packet["goal_binding"]) == canonical_value(goal_binding)
      raise ContractError, "existing context Goal binding does not match the current native Goal and cannot be overwritten"
    end
    validate_rendered_context_bytes!(root, packet_bytes)
    expected_pack = rebuild_expected_pack!(root, snapshot_relative)
    unless canonical_value(packet.fetch("role_context_pack")) == canonical_value(expected_pack)
      raise ContractError, "existing role_context_pack does not equal IdolRoleContextPack.build_from_dispatch on the launched snapshot"
    end
    expected_prompt = expected_worker_prompt(document, expected_pack)
    unless packet.fetch("worker_prompt").to_s == expected_prompt
      raise ContractError, "existing worker_prompt is not original compiled prompt + root directive + render_runtime_json(exact pack)"
    end
    pack_errors = IdolRoleContextPack.validate_pack(root: root, pack: expected_pack, validation_mode: "active_promotion")
    raise ContractError, "existing role context pack failed active_promotion revalidation: #{pack_errors.join('; ')}" unless pack_errors.empty?
    recheck_selected_input!(selected, "launched dispatch after immutable reuse")
    packet_result(context_relative, packet_bytes)
  end

  def rebuild_expected_pack!(root, snapshot_relative)
    pack = IdolRoleContextPack.build_from_dispatch(root: root, dispatch_path: snapshot_relative)
    writer = pack.dig("activation_binding", "writer").to_s
    writer = IdolRoleContextPack::LEGACY_WRITER if writer.empty?
    if writer == IdolRoleContextPack::GRAPH_WRITER || pack.key?("graph_dispatch_identity")
      raise ContractError, "Graph v2 Role Context Pack writer is refused for department runtime context"
    end
    unless writer == IdolRoleContextPack::LEGACY_WRITER
      raise ContractError, "unsupported Role Context Pack writer: #{writer}"
    end
    pack_errors = IdolRoleContextPack.validate_pack(root: root, pack: pack, validation_mode: "active_promotion")
    raise ContractError, "role context pack failed active_promotion validation: #{pack_errors.join('; ')}" unless pack_errors.empty?
    raise ContractError, "role context pack status is not pass" unless pack["status"].to_s == "pass"
    provider = pack.fetch("provider_binding")
    unless provider["provider"].to_s == REQUIRED_PROVIDER &&
           provider["exact_model"].to_s == REQUIRED_MODEL &&
           provider["reasoning_effort"].to_s == REQUIRED_EFFORT
      raise ContractError, "selected provider must be exact grok-4.6/xhigh"
    end
    pack
  end

  def expected_worker_prompt(document, pack)
    rendered_prompt = document.fetch("launch").fetch("compiled_launch_prompt").fetch("rendered_prompt").to_s
    raise ContractError, "compiled launch rendered prompt is missing" if rendered_prompt.empty?
    "#{rendered_prompt}\n\n#{INSTRUCTION_DELIVERY_DIRECTIVE}\n#{IdolRoleContextPack.render_runtime_json(pack)}"
  end

  def render_context_bytes(document:, goal_binding:, input_digest:, snapshot_relative:, snapshot_sha256:, prepared_at:, pack:)
    worker_prompt = expected_worker_prompt(document, pack)
    context = {
      "schema_version" => SCHEMA_VERSION,
      "authority" => AUTHORITY,
      "dispatch_id" => document.fetch("dispatch_id").to_s,
      "run" => document.fetch("run").to_s,
      "attempt_id" => document.fetch("lineage").fetch("attempt_id").to_s,
      "dispatch_input_sha256" => input_digest,
      "source_dispatch" => {
        "path" => snapshot_relative,
        "sha256" => snapshot_sha256
      },
      "goal_binding" => goal_binding,
      "prepared_at" => prepared_at,
      "role_context_pack" => pack,
      "worker_prompt" => worker_prompt,
      "worker_prompt_sha256" => Digest::SHA256.hexdigest(worker_prompt)
    }
    utf8_bytes!(JSON.pretty_generate(context) + "\n", "department runtime context")
  end

  def validate_rendered_context_bytes!(root, packet_bytes)
    Tempfile.create(["idol-department-runtime-context", ".json"]) do |file|
      file.write(packet_bytes)
      file.flush
      file.fsync
      validate_owning_schema!(
        root: root,
        schema_relative: SCHEMA_RELATIVE,
        instance_path: file.path,
        label: "department runtime context"
      )
    end
  end

  def load_validated_context_packet!(root:, document:, receipt:)
    expected_snapshot, expected_context = derived_context_paths(
      document.fetch("run"),
      document.fetch("dispatch_id"),
      document.fetch("lineage").fetch("attempt_id")
    )
    unless receipt.fetch("context_packet").fetch("path") == expected_context
      raise ContractError, "role context receipt context_packet path is not the derived context file"
    end
    selected = capture_selected_file!(
      root,
      receipt.fetch("context_packet").fetch("path"),
      label: "context packet",
      run: document.fetch("run").to_s
    )
    actual_sha = selected.sha256
    unless actual_sha == receipt.fetch("context_packet").fetch("sha256")
      raise ContractError, "role context receipt context_packet SHA-256 does not match the live context file"
    end
    packet_bytes = utf8_bytes!(selected.bytes, "context packet")
    validate_owning_schema!(root: root, schema_relative: SCHEMA_RELATIVE, instance_path: selected.path, label: "department runtime context")
    packet = JSON.parse(packet_bytes)
    raise ContractError, "department runtime context must be one JSON object" unless packet.is_a?(Hash)
    reject_unknown_keys!(packet, CONTEXT_FIELDS, "department runtime context")
    assert_context_envelope!(packet, document, expected_snapshot, actual_sha)
    [packet, packet_bytes, actual_sha, expected_snapshot, expected_context]
  end

  def packet_result(relative, packet_bytes)
    {
      "context_packet" => {
        "path" => relative,
        "sha256" => Digest::SHA256.hexdigest(packet_bytes)
      },
      "packet_text" => packet_bytes
    }
  end

  def assert_current_v8_launched_dispatch!(root, selected, document)
    assert_v8_dispatch_identity!(document)
    unless document.dig("lifecycle", "current_state").to_s == "launched"
      raise ContractError, "department context prepare requires a current launched v8 dispatch"
    end
    unless document.dig("launch", "instruction_delivery").to_s == INSTRUCTION_DELIVERY
      raise ContractError, "department context prepare requires launch.instruction_delivery=role_context_pack"
    end
    run = document.fetch("run").to_s
    dispatch_id = document.fetch("dispatch_id").to_s
    expected_relative = "#{run}/work/department-dispatches/#{dispatch_id}.yaml"
    unless selected.relative == expected_relative
      raise ContractError, "department dispatch must live at #{expected_relative}"
    end
    assert_provider_and_writer!(document)
    validator = root.join(DISPATCH_VALIDATOR_RELATIVE)
    raise ContractError, "department dispatch validator is missing" unless validator.file?
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      validator.to_s,
      "--json",
      selected.relative,
      chdir: root.to_s
    )
    payload = begin
      JSON.parse(stdout)
    rescue JSON::ParserError
      {}
    end
    unless status.success? && payload["status"].to_s == "pass"
      details = Array(payload["errors"]).join("; ")
      details = [stderr, stdout].join(" ").strip if details.empty?
      raise ContractError, "current v8 launched dispatch failed validation: #{truncate_error(details)}"
    end
  end

  def assert_v8_dispatch_identity!(document)
    raise ContractError, "department dispatch must be an object" unless document.is_a?(Hash)
    version = document["schema_version"].to_s
    if version == GRAPH_DISPATCH_SCHEMA || document["artifact_type"].to_s == "graph_department_dispatch"
      raise ContractError, "Graph v2 department dispatch is refused"
    end
    unless version == DISPATCH_SCHEMA_VERSION && document["artifact_type"].to_s == "department_dispatch"
      raise ContractError, "department context requires an actual idol-department-dispatch.v8 document"
    end
    %w[dispatch_id run lineage review_submission launch routing_identity].each do |field|
      raise ContractError, "department dispatch #{field} is missing" if document[field].nil?
    end
    lineage = document["lineage"]
    raise ContractError, "department dispatch lineage must be an object" unless lineage.is_a?(Hash)
    unless lineage["attempt_id"].to_s == document["dispatch_id"].to_s
      raise ContractError, "lineage attempt_id must equal dispatch_id"
    end
    raise ContractError, "lineage session_id is missing" if lineage["session_id"].to_s.empty?
  end

  def assert_provider_and_writer!(document)
    lineage = document.fetch("lineage")
    routing = document.fetch("routing_identity")
    raise ContractError, "Graph v2 Role Context Pack writer is refused" if routing["writer"].to_s == IdolRoleContextPack::GRAPH_WRITER
    unless lineage["provider"].to_s == REQUIRED_PROVIDER && routing["provider"].to_s == REQUIRED_PROVIDER
      raise ContractError, "department context refuses a provider other than grok"
    end
    unless lineage["runtime_surface"].to_s == REQUIRED_RUNTIME_SURFACE
      raise ContractError, "department context requires runtime_surface grok_build_cli_acp"
    end
    unless routing["resolved_provider_model"].to_s == REQUIRED_MODEL && routing["reasoning_effort"].to_s == REQUIRED_EFFORT
      raise ContractError, "selected provider must be exact grok-4.6/xhigh"
    end
  end

  def normalize_goal_binding!(value, document)
    raise ContractError, "runtime_goal must be an object" unless value.is_a?(Hash)
    keys = value.keys.map(&:to_s)
    extras = keys - GOAL_BINDING_FIELDS
    missing = GOAL_BINDING_FIELDS - keys
    raise ContractError, "runtime_goal is missing #{missing.sort.join(', ')}" unless missing.empty?
    unless extras.empty?
      unknown = extras - ADAPTER_GOAL_FIELDS
      raise ContractError, "runtime_goal has unknown fields: #{unknown.sort.join(', ')}" unless unknown.empty?
      unless extras.sort == ADAPTER_GOAL_FIELDS.sort
        raise ContractError, "runtime_goal adapter object must include state, command, turn_id, and provider_prompt_id"
      end
      ADAPTER_GOAL_FIELDS.each do |field|
        raw = value.key?(field) ? value[field] : value[field.to_sym]
        raise ContractError, "runtime_goal.#{field} must be preserved exactly" if raw.nil? || raw.to_s.empty?
      end
    end
    lineage = document.fetch("lineage")
    launch = document.fetch("launch")
    task = launch.fetch("task")
    goal_contract = launch.fetch("goal_contract")
    binding = GOAL_BINDING_FIELDS.each_with_object({}) do |field, result|
      raw = value.key?(field) ? value[field] : value[field.to_sym]
      result[field] = raw
    end
    unless binding["provider"] == REQUIRED_PROVIDER
      raise ContractError, "runtime_goal.provider must be grok"
    end
    unless binding["runtime_surface"] == REQUIRED_RUNTIME_SURFACE
      raise ContractError, "runtime_goal.runtime_surface must be grok_build_cli_acp"
    end
    unless binding["evidence_source"] == REQUIRED_EVIDENCE_SOURCE
      raise ContractError, "runtime_goal.evidence_source must be grok_acp_goal_updated_event"
    end
    %w[native_goal_id native_session_id assignment_key request_id objective].each do |field|
      raise ContractError, "runtime_goal.#{field} must be a non-empty string" unless binding[field].is_a?(String) && !binding[field].empty?
    end
    expected_key = assignment_key_from_owner(launch.fetch("authority").fetch("assigned_owner"))
    unless binding["assignment_key"].to_s == expected_key
      raise ContractError, "runtime_goal.assignment_key must bind launch assigned_owner"
    end
    unless binding["dispatch_id"].to_s == document.fetch("dispatch_id").to_s
      raise ContractError, "runtime_goal.dispatch_id must equal the current dispatch_id"
    end
    unless binding["attempt_id"].to_s == lineage.fetch("attempt_id").to_s
      raise ContractError, "runtime_goal.attempt_id must equal lineage.attempt_id"
    end
    unless binding["native_session_id"].to_s == lineage.fetch("session_id").to_s
      raise ContractError, "runtime_goal.native_session_id must equal lineage.session_id"
    end
    unless binding["objective"].to_s == task.fetch("objective").to_s && binding["objective"].to_s == goal_contract.fetch("goal_text").to_s
      raise ContractError, "runtime_goal.objective must exact-copy launch.task.objective and goal_contract.goal_text"
    end
    expected_hash = Digest::SHA256.hexdigest(binding["objective"].to_s)
    unless binding["goal_text_sha256"].to_s == expected_hash && binding["goal_text_sha256"].to_s == goal_contract.fetch("goal_text_sha256").to_s
      raise ContractError, "runtime_goal.goal_text_sha256 is stale"
    end
    normalize_sha256!(binding["raw_event_sha256"], "runtime_goal.raw_event_sha256")
    parse_timestamp!(binding["observed_at"], "runtime_goal.observed_at")
    binding
  end

  def normalize_receipt!(value)
    raise ContractError, "application receipt must be an object" unless value.is_a?(Hash)
    reject_unknown_keys!(value, RECEIPT_FIELDS, "application receipt")
    RECEIPT_FIELDS.each do |field|
      raise ContractError, "application receipt #{field} is missing" if value[field].nil?
    end
    unless value["schema_version"].to_s == RECEIPT_SCHEMA_VERSION
      raise ContractError, "application receipt schema_version is not active"
    end
    pointer = value["context_packet"]
    raise ContractError, "application receipt context_packet must be an object" unless pointer.is_a?(Hash)
    reject_unknown_keys!(pointer, POINTER_FIELDS, "application receipt context_packet")
    raise ContractError, "application receipt context_packet.path is missing" if pointer["path"].to_s.empty?
    normalize_sha256!(pointer["sha256"], "application receipt context_packet.sha256")
    %w[dispatch_id attempt_id native_goal_id native_session_id pack_id].each do |field|
      raise ContractError, "application receipt #{field} must be a non-empty string" unless value[field].is_a?(String) && !value[field].empty?
    end
    %w[dispatch_input_sha256 native_goal_raw_event_sha256 pack_digest source_set_sha256 instruction_content_sha256].each do |field|
      normalize_sha256!(value[field], "application receipt #{field}")
    end
    parse_timestamp!(value["applied_at"], "application receipt applied_at")
    value
  end

  def assert_context_envelope!(packet, document, expected_snapshot, actual_sha)
    unless packet["schema_version"].to_s == SCHEMA_VERSION
      raise ContractError, "department runtime context schema_version is not active"
    end
    unless packet["authority"].to_s == AUTHORITY
      raise ContractError, "department runtime context authority is invalid"
    end
    unless packet["dispatch_id"].to_s == document.fetch("dispatch_id").to_s
      raise ContractError, "department runtime context dispatch_id does not match the current dispatch"
    end
    unless packet["run"].to_s == document.fetch("run").to_s
      raise ContractError, "department runtime context run does not match the current dispatch"
    end
    unless packet["attempt_id"].to_s == document.fetch("lineage").fetch("attempt_id").to_s
      raise ContractError, "department runtime context attempt_id does not match the current dispatch"
    end
    pointer = packet["source_dispatch"]
    raise ContractError, "source_dispatch must be an object" unless pointer.is_a?(Hash)
    reject_unknown_keys!(pointer, POINTER_FIELDS, "source_dispatch")
    unless pointer["path"].to_s == expected_snapshot
      raise ContractError, "source_dispatch.path is not the derived launched snapshot"
    end
    normalize_sha256!(pointer["sha256"], "source_dispatch.sha256")
    unless actual_sha.match?(SHA256_PATTERN)
      raise ContractError, "context packet SHA-256 is invalid"
    end
  end

  def assert_immutable_launch_binding!(snapshot, document, expected_input_digest)
    %w[lineage review_submission launch].each do |field|
      unless canonical_value(snapshot[field]) == canonical_value(document[field])
        raise ContractError, "current dispatch #{field} does not match the immutable launched snapshot"
      end
    end
    actual = structured_sha256(
      "lineage" => document.fetch("lineage"),
      "review_submission" => document.fetch("review_submission"),
      "launch" => document.fetch("launch")
    )
    unless actual == expected_input_digest
      raise ContractError, "dispatch_input_sha256 does not match current lineage, review_submission, and launch"
    end
  end

  def assert_receipt_matches_packet!(receipt, packet, pack, expected_context, actual_sha, goal_binding)
    unless receipt.fetch("context_packet").fetch("path") == expected_context &&
           receipt.fetch("context_packet").fetch("sha256") == actual_sha
      raise ContractError, "application receipt context_packet does not match the live context file"
    end
    unless receipt["dispatch_id"].to_s == packet["dispatch_id"].to_s &&
           receipt["attempt_id"].to_s == packet["attempt_id"].to_s
      raise ContractError, "application receipt dispatch/attempt does not match the context packet"
    end
    unless receipt["dispatch_input_sha256"].to_s == packet["dispatch_input_sha256"].to_s
      raise ContractError, "application receipt dispatch_input_sha256 does not match the context packet"
    end
    unless receipt["native_goal_id"].to_s == goal_binding["native_goal_id"].to_s &&
           receipt["native_session_id"].to_s == goal_binding["native_session_id"].to_s &&
           receipt["native_goal_raw_event_sha256"].to_s == goal_binding["raw_event_sha256"].to_s
      raise ContractError, "application receipt native Goal fields do not match the frozen Goal binding"
    end
    projection = pack.fetch("projection")
    unless receipt["pack_id"].to_s == pack["pack_id"].to_s &&
           receipt["pack_digest"].to_s == projection["pack_digest"].to_s &&
           receipt["source_set_sha256"].to_s == projection["source_set_sha256"].to_s &&
           receipt["instruction_content_sha256"].to_s == projection["instruction_content_sha256"].to_s
      raise ContractError, "application receipt pack identity does not match the frozen Role Context Pack"
    end
  end

  def assert_application_timeline!(observed_at:, prepared_at:, applied_at:, work_started_at:, returned_at:)
    observed = parse_timestamp!(observed_at, "goal observed_at")
    prepared = parse_timestamp!(prepared_at, "prepared_at")
    applied = parse_timestamp!(applied_at, "applied_at")
    started = parse_timestamp!(work_started_at, "work_started_at")
    returned = parse_timestamp!(returned_at, "returned_at")
    unless observed <= prepared && prepared <= applied && applied <= started && started <= returned
      raise ContractError, "Goal observed_at <= prepared_at <= applied_at <= work_started_at <= returned_at is required"
    end
  end

  def derived_context_paths(run, dispatch_id, attempt_id)
    safe_id!(dispatch_id, "dispatch_id")
    safe_id!(attempt_id, "attempt_id")
    raise ContractError, "run must be a runs/ path" unless run.to_s.start_with?("runs/")
    raise ContractError, "run escapes derived context directory" if run.to_s.split("/").include?("..")
    base = "#{run}/work/department-dispatches/contexts/#{dispatch_id}"
    ["#{base}/#{attempt_id}.launched.yaml", "#{base}/#{attempt_id}.context.json"]
  end

  def capture_selected_file!(root, raw, label:, run: nil)
    path, relative = resolve_contained_relative(root, raw, label)
    if run
      unless relative == run || relative.start_with?("#{run}/")
        raise ContractError, "#{label} resolves outside the declared run"
      end
    end
    ancestors = lstat_chain!(root, relative, label, leaf_kind: :file, create: false)
    bytes, stat = read_nofollow_regular_file!(path, label)
    if bytes.bytesize > MAX_DISPATCH_BYTES
      raise ContractError, "#{label} exceeds the bounded input size"
    end
    SelectedInput.new(
      root: root,
      path: path,
      relative: relative,
      bytes: bytes,
      sha256: Digest::SHA256.hexdigest(bytes),
      dev: stat.dev,
      ino: stat.ino,
      nlink: stat.nlink,
      size: stat.size,
      ancestors: ancestors
    )
  end

  def recheck_selected_input!(selected, label)
    st = File.lstat(selected.path.to_s)
    if st.symlink? || !st.file? || st.nlink != 1
      raise ContractError, "#{label} changed link type and cannot be used"
    end
    if st.dev != selected.dev || st.ino != selected.ino || st.nlink != selected.nlink || st.size != selected.size
      raise ContractError, "#{label} device/inode changed and cannot be used"
    end
    selected.ancestors.each do |row|
      ast = File.lstat(row.fetch(:path).to_s)
      if ast.symlink? || ast.dev != row[:dev] || ast.ino != row[:ino]
        raise ContractError, "#{label} ancestor path changed and cannot be used"
      end
    end
    bytes, = read_nofollow_regular_file!(selected.path, label)
    unless bytes == selected.bytes
      raise ContractError, "#{label} bytes changed and cannot be used"
    end
  end

  def resolve_contained_relative(root, raw, label)
    raise ContractError, "#{label} path is missing" if raw.to_s.empty?
    path = Pathname.new(raw.to_s)
    raise ContractError, "#{label} must be repository-relative" if path.absolute?
    raise ContractError, "#{label} escapes repository" if path.each_filename.any? { |part| part == ".." }
    path = root.join(path).expand_path.cleanpath
    relative = relative_from!(root, path, label)
    [path, relative]
  end

  def lstat_chain!(root, relative, label, leaf_kind:, create:)
    parts = relative.split("/").reject(&:empty?)
    raise ContractError, "#{label} path is missing" if parts.empty?
    current = root
    root_stat = File.lstat(current.to_s)
    if root_stat.symlink? || !root_stat.directory?
      raise ContractError, "root must be a real directory"
    end
    ancestors = [{path: current, dev: root_stat.dev, ino: root_stat.ino}]
    parts.each_with_index do |part, index|
      raise ContractError, "#{label} path is not legal" if part == "." || part == ".." || part.empty?
      nxt = current.join(part)
      last = index == parts.length - 1
      st = begin
        File.lstat(nxt.to_s)
      rescue Errno::ENOENT
        nil
      end
      if st
        if st.symlink?
          raise ContractError, "#{label} path component must not be a symlink: #{part}"
        end
        if last && leaf_kind == :file
          raise ContractError, "#{label} is not a file" unless st.file?
          raise ContractError, "#{label} must not be a hardlink" if st.nlink != 1
        else
          raise ContractError, "#{label} path component is not a directory: #{part}" unless st.directory?
        end
        ancestors << {path: nxt, dev: st.dev, ino: st.ino} unless last && leaf_kind == :file
      else
        unless create && !(last && leaf_kind == :file)
          raise ContractError, "#{label} is missing: #{relative}"
        end
        Dir.mkdir(nxt.to_s)
        created = File.lstat(nxt.to_s)
        if created.symlink? || !created.directory?
          raise ContractError, "#{label} created path is not a real directory: #{part}"
        end
        ancestors << {path: nxt, dev: created.dev, ino: created.ino}
      end
      current = nxt
    end
    ancestors
  end

  def ensure_directory_chain!(root, relative, run:)
    raise ContractError, "context directory resolves outside the declared run" unless relative == run || relative.start_with?("#{run}/")
    lstat_chain!(root, relative, "context directory", leaf_kind: :directory, create: true)
    root.join(relative)
  end

  def contained_regular_file!(root, raw, label:)
    path, = resolve_contained_relative(root, raw, label)
    lstat_chain!(root, path.relative_path_from(root).to_s, label, leaf_kind: :file, create: false)
    path
  end

  def exclusive_publish!(path, bytes)
    raise ContractError, "refusing to overwrite #{path.basename}" if path_exists_nofollow?(path)
    tmp = path.dirname.join(".#{path.basename}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
    begin
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o644) do |file|
        file.write(bytes)
        file.flush
        file.fsync
        st = file.stat
        raise ContractError, "temporary publication is not a regular one-link file" unless st.file? && st.nlink == 1
      end
      File.link(tmp.to_s, path.to_s)
    rescue Errno::EEXIST
      raise ContractError, "department context metadata already exists and cannot be overwritten"
    ensure
      File.delete(tmp.to_s) if tmp && File.exist?(tmp.to_s)
    end
  end

  def open_publish_lock!(lock_path)
    File.open(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o644) do |lock|
      st = lock.stat
      unless st.file? && st.nlink == 1
        raise ContractError, "publish lock must be a regular one-link file"
      end
      identity = [st.dev, st.ino]
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        raise ContractError, "department context publish is already locked for this dispatch"
      end
      locked = lock.stat
      unless locked.file? && locked.nlink == 1 && [locked.dev, locked.ino] == identity
        raise ContractError, "publish lock identity changed"
      end
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end

  def read_nofollow_regular_file!(path, label)
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      st = file.stat
      raise ContractError, "#{label} is not a file" unless st.file?
      raise ContractError, "#{label} must not be a hardlink" if st.nlink != 1
      bytes = file.read
      [bytes, st]
    end
  rescue Errno::ELOOP
    raise ContractError, "#{label} must not be a symlink"
  end

  def read_nofollow_file_bytes!(path, label)
    bytes, = read_nofollow_regular_file!(path, label)
    bytes
  end

  def path_exists_nofollow?(path)
    File.lstat(path.to_s)
    true
  rescue Errno::ENOENT
    false
  end

  def regular_file_one_link?(path)
    st = File.lstat(path.to_s)
    !st.symlink? && st.file? && st.nlink == 1
  rescue Errno::ENOENT
    false
  end

  def relative_from!(root, path, label)
    relative = path.relative_path_from(root).to_s
    if relative == ".." || relative.start_with?("../")
      raise ContractError, "#{label} escapes repository: #{path}"
    end
    relative
  rescue ArgumentError
    raise ContractError, "#{label} escapes repository: #{path}"
  end

  def load_mapping_bytes(bytes, label)
    text = utf8_bytes!(bytes, label)
    value = if label.to_s.end_with?(".json")
              JSON.parse(text)
            else
              YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
            end
    raise ContractError, "document must be an object: #{label}" unless value.is_a?(Hash)
    value
  rescue JSON::ParserError, Psych::Exception => e
    raise ContractError, "cannot parse #{label}: #{e.message}"
  end

  def utf8_bytes!(bytes, label)
    text = bytes.to_s.dup.force_encoding(Encoding::UTF_8)
    raise ContractError, "#{label} is not valid UTF-8" unless text.valid_encoding?
    text
  end

  def normalize_sha256!(value, label)
    text = value.to_s
    raise ContractError, "#{label} must be a SHA-256 hex digest" unless text.match?(SHA256_PATTERN)
    text
  end

  def safe_id!(value, label)
    text = value.to_s
    raise ContractError, "#{label} is not a legal identifier" unless text.match?(ID_PATTERN)
    text
  end

  def reject_unknown_keys!(hash, allowed, label)
    raise ContractError, "#{label} must be an object" unless hash.is_a?(Hash)
    extra = hash.keys.map(&:to_s) - allowed
    raise ContractError, "#{label} has unknown fields: #{extra.sort.join(', ')}" unless extra.empty?
  end

  def parse_timestamp!(value, label)
    DateTime.iso8601(value.to_s)
  rescue ArgumentError
    raise ContractError, "#{label} must be an ISO-8601 timestamp"
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_s).sort.each_with_object({}) do |key, result|
        original = value.key?(key) ? key : value.keys.find { |candidate| candidate.to_s == key }
        result[key] = canonical_value(value[original])
      end
    when Array
      value.map { |item| canonical_value(item) }
    when Date, Time, DateTime
      value.iso8601
    else
      value
    end
  end

  def structured_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end

  def python_bin
    path = IMPLEMENTATION_ROOT.join("scripts", "idol-video-python")
    raise ContractError, "idol-video-python is missing" unless path.exist?
    path
  end
end
