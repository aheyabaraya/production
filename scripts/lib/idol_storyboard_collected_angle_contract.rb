# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "yaml"
require_relative "idol_02a_storyboard_contract"

# Structural completeness for model-authored full-storyboard camera-angle
# review. Scripts never infer sameness, uniqueness, or pixel adequacy from
# labels, families, text inequality, fuzzy similarity, or numeric angles.
module IdolStoryboardCollectedAngleContract
  CONTRACT_VERSION = "collected_storyboard_camera_angle_review.v1"
  SCOPE = "all_distinct_generated_production_images_on_the_planning_production_storyboard"
  DECLARED_RESULTS = %w[differs exact_carry founder_lock_hold same].freeze
  GEOMETRY_FIELDS = %w[camera_height direction_angle].freeze

  module_function

  def value_sha256(value)
    Idol02AStoryboardContract.value_sha256(value)
  end

  def geometry_payload(spec)
    spec = {} unless spec.is_a?(Hash)
    direction = spec["direction_angle"].to_s.strip
    direction = spec["camera_angle"].to_s.strip if direction.empty?
    {
      "camera_height" => spec["camera_height"].to_s,
      "direction_angle" => direction
    }
  end

  def geometry_projection_sha(spec)
    payload = geometry_payload(spec)
    return nil if payload["camera_height"].strip.empty? || payload["direction_angle"].strip.empty?

    value_sha256(payload)
  end

  def geometry_value_sha(spec)
    geometry_projection_sha(spec)
  end

  def image_key(image)
    sha = image.to_h["image_sha256"].to_s
    return sha unless sha.empty?

    image.to_h["cut_id"].to_s
  end

  def distinct_images(images)
    Array(images).each_with_object([]) do |image, collected|
      next unless image.is_a?(Hash)

      key = image_key(image)
      next if key.empty?
      next if collected.any? { |row| image_key(row) == key }

      collected << image
    end
  end

  def expected_pair_keys(images)
    keys = distinct_images(images).map { |image| image_key(image) }
    keys.combination(2).map { |left, right| [left, right].sort }
  end

  def pair_key(pair)
    [
      pair.to_h["left_image_sha256"].to_s.empty? ? pair.to_h["left_cut_id"].to_s : pair.to_h["left_image_sha256"].to_s,
      pair.to_h["right_image_sha256"].to_s.empty? ? pair.to_h["right_cut_id"].to_s : pair.to_h["right_image_sha256"].to_s
    ].sort
  end

  def resolve_pointer(document, pointer)
    raise KeyError, "JSON pointer must begin with /" unless pointer.to_s.start_with?("/")

    pointer.split("/").drop(1).reduce(document) do |value, token|
      key = token.gsub("~1", "/").gsub("~0", "~")
      value.is_a?(Array) ? value.fetch(Integer(key, 10)) : value.fetch(key)
    end
  end

  def load_mapping(path)
    text = path.read
    path.extname.downcase == ".json" ? JSON.parse(text) : YAML.safe_load(text, aliases: true)
  end

  def inside_repo?(path, root)
    relative = path.expand_path.cleanpath.relative_path_from(root.expand_path.cleanpath).to_s
    relative != ".." && !relative.start_with?("../")
  rescue ArgumentError
    false
  end

  def storyboard_production_images(document)
    images = []
    Array(document.to_h["master_storyboard"]).each_with_index do |core, core_index|
      imported = core.to_h["imported_core"].is_a?(Hash) ? core["imported_core"] : {}
      camera = imported["camera"].is_a?(Hash) ? imported["camera"] : {}
      camera_pointer = "/master_storyboard/#{core_index}/imported_core/camera"
      images << {
        "cut_id" => core["core_cut_id"].to_s,
        "production_cut_type" => "official_core",
        "section_id" => (imported["section_id"] || core["section_id"]).to_s,
        "image_sha256" => imported.dig("primary_image", "sha256").to_s,
        "still_camera_spec" => camera,
        "still_camera_binding" => {
          "source_json_pointer" => camera_pointer,
          "source_value_sha256" => value_sha256(camera)
        },
        "geometry_projection_sha256" => geometry_projection_sha(camera)
      }
      Array(core.dig("compile_seed", "branch_cuts")).each_with_index do |branch, branch_index|
        spec = branch.to_h["still_camera_spec"].is_a?(Hash) ? branch["still_camera_spec"] : {}
        spec_pointer = "/master_storyboard/#{core_index}/compile_seed/branch_cuts/#{branch_index}/still_camera_spec"
        images << {
          "cut_id" => branch["branch_cut_id"].to_s,
          "production_cut_type" => "branch",
          "section_id" => branch["section_id"].to_s,
          "image_sha256" => "",
          "still_camera_spec" => spec,
          "still_camera_binding" => {
            "source_json_pointer" => spec_pointer,
            "source_value_sha256" => value_sha256(spec)
          },
          "geometry_projection_sha256" => geometry_projection_sha(spec)
        }
      end
    end
    images
  end

  def bound_lock_identity_texts(value)
    if value.is_a?(Hash)
      [value["lock_id"], value["id"], value["lock"], value["verbatim"]].map do |item|
        item.is_a?(Hash) || item.is_a?(Array) ? "" : item.to_s
      end
    else
      [value.to_s]
    end
  end

  def lock_id_present_in_bound_source?(value, lock_id)
    wanted = lock_id.to_s
    return false if wanted.empty?

    bound_lock_identity_texts(value).any? { |text| !text.empty? && text == wanted }
  end

  def founder_exception_errors(exception, pair, root)
    return [] if exception.nil?
    return ["#{pair_label(pair)} founder exception must be an object or null"] unless exception.is_a?(Hash)

    errors = []
    %w[lock_id source_path source_json_pointer source_value_sha256 conflicting_repeat_reason].each do |key|
      errors << "#{pair_label(pair)} founder exception missing #{key}" if exception[key].to_s.strip.empty?
    end
    named_cuts = Array(exception["named_cut_ids"]).map(&:to_s)
    named_shas = Array(exception["named_image_sha256s"]).map(&:to_s)
    pair_cuts = [pair["left_cut_id"], pair["right_cut_id"]].map(&:to_s)
    pair_shas = [pair["left_image_sha256"], pair["right_image_sha256"]].map(&:to_s).reject(&:empty?)
    unless pair_cuts.all? { |cut| named_cuts.include?(cut) } || (pair_shas.length == 2 && pair_shas.all? { |sha| named_shas.include?(sha) })
      errors << "#{pair_label(pair)} founder exception does not name the exact pair cuts or image SHA-256 values"
    end
    return errors unless errors.empty?

    path = Pathname.new(exception["source_path"])
    path = root.join(path) unless path.absolute?
    unless inside_repo?(path, root) && path.file?
      return errors + ["#{pair_label(pair)} founder exception source_path is missing or unbound"]
    end

    begin
      document = load_mapping(path)
      value = resolve_pointer(document, exception["source_json_pointer"])
    rescue JSON::ParserError, Psych::Exception, KeyError, IndexError, ArgumentError, TypeError => error
      return errors + ["#{pair_label(pair)} founder exception source pointer does not resolve: #{error.message}"]
    end

    actual = value_sha256(value)
    unless actual == exception["source_value_sha256"].to_s
      errors << "#{pair_label(pair)} founder exception source_value_sha256 is stale or unbound"
    end
    unless lock_id_present_in_bound_source?(value, exception["lock_id"])
      errors << "#{pair_label(pair)} founder exception lock_id is not present in the bound Founder source"
    end
    errors
  end

  def pair_label(pair)
    "#{pair.to_h['left_cut_id']}/#{pair.to_h['right_cut_id']}"
  end

  def images_for_section(images, section_id)
    Array(images).select { |image| image.to_h["section_id"].to_s == section_id.to_s }
  end

  def validate_review(review:, expected_images:, document:, root:, parent_verdict:, label:, require_generated_pixels: false)
    errors = []
    unless review.is_a?(Hash)
      return ["#{label} collected_image_camera_angle_review is missing"]
    end

    errors << "#{label} contract_version must be #{CONTRACT_VERSION}" unless review["contract_version"].to_s == CONTRACT_VERSION
    errors << "#{label} scope must be the full planning/production storyboard collection" unless review["scope"].to_s == SCOPE
    errors << "#{label} automatic_creative_pass must be false" unless review["automatic_creative_pass"] == false
    errors << "#{label} contextual_full_storyboard_read is missing" if review["contextual_full_storyboard_read"].to_s.strip.empty?
    if require_generated_pixels
      missing = expected_images.select { |image| image.to_h["image_sha256"].to_s.empty? }
      declared = Array(review["incomplete_pixel_bindings"]).map(&:to_s).sort
      actual = missing.map { |image| image["cut_id"].to_s }.sort
      errors << "#{label} incomplete_pixel_bindings must name generated images that are not yet bound" unless declared == actual
      if missing.any?
        errors << "#{label} generated-pixel review is incomplete until actual passed image bindings are present" unless review["generated_pixel_closure"] == false
        errors << "#{label} cannot claim generated-pixel review for unavailable images #{actual.join(', ')}" if review["generated_pixel_closure"] == true
        errors << "#{label} passed generated-pixel review cannot remain incomplete" if parent_verdict.to_s == "pass"
      elsif parent_verdict.to_s == "pass" && review["generated_pixel_closure"] != true
        errors << "#{label} passed generated-pixel review requires generated_pixel_closure true"
      end
    else
      errors << "#{label} planning review cannot claim generated_pixel_closure" if review["generated_pixel_closure"] == true
    end

    expected = distinct_images(expected_images)
    actual = Array(review["distinct_images"])
    expected_ids = expected.map { |image| image["cut_id"].to_s }.sort
    actual_ids = actual.map { |image| image.to_h["cut_id"].to_s }.sort
    errors << "#{label} distinct_images must exact-cover every Official Core primary and Branch still" unless expected_ids == actual_ids

    actual.each do |image|
      expected_row = expected.find { |row| row["cut_id"].to_s == image.to_h["cut_id"].to_s }
      next unless expected_row

      binding = image.to_h["still_camera_binding"].to_h
      errors << "#{label} #{image['cut_id']} still_camera_binding pointer differs" unless binding["source_json_pointer"].to_s == expected_row.dig("still_camera_binding", "source_json_pointer").to_s
      begin
        source = resolve_pointer(document, binding["source_json_pointer"].to_s)
        actual_sha = value_sha256(source)
        actual_geo = geometry_projection_sha(source)
      rescue KeyError, IndexError, ArgumentError
        actual_sha = nil
        actual_geo = nil
        errors << "#{label} #{image['cut_id']} still_camera_binding pointer does not resolve"
      end
      errors << "#{label} #{image['cut_id']} still_camera_binding source_value_sha256 must hash the exact pointer target, not a geometry projection" unless binding["source_value_sha256"].to_s == actual_sha.to_s && !actual_sha.to_s.empty?
      declared_geo = image["geometry_projection_sha256"].to_s
      errors << "#{label} #{image['cut_id']} geometry_projection_sha256 is missing or stale" unless declared_geo == actual_geo.to_s && !declared_geo.empty? && !actual_geo.to_s.empty?
      expected_sha = expected_row["image_sha256"].to_s
      next if expected_sha.empty?

      errors << "#{label} #{image['cut_id']} image_sha256 differs from the bound production still" unless image["image_sha256"].to_s == expected_sha
    end

    expected_keys = expected_pair_keys(expected)
    pairs = Array(review["pairs"])
    actual_keys = pairs.map { |pair| pair_key(pair) }.sort
    errors << "#{label} pairs must be the complete unordered set of distinct images, not adjacent-only" unless actual_keys == expected_keys.sort
    errors << "#{label} pair count must equal C(n,2) over distinct images" unless pairs.length == expected_keys.length

    by_cut = actual.each_with_object({}) { |image, memo| memo[image.to_h["cut_id"].to_s] = image }
    pairs.each do |pair|
      next unless pair.is_a?(Hash)

      left = by_cut[pair["left_cut_id"].to_s]
      right = by_cut[pair["right_cut_id"].to_s]
      errors << "#{label} #{pair_label(pair)} is not in distinct_images" if left.nil? || right.nil?
      next if left.nil? || right.nil?

      left_sha = pair["left_image_sha256"].to_s
      right_sha = pair["right_image_sha256"].to_s
      unless left_sha.empty? || left_sha == left["image_sha256"].to_s
        errors << "#{label} #{pair_label(pair)} left_image_sha256 does not exact-bind distinct_images"
      end
      unless right_sha.empty? || right_sha == right["image_sha256"].to_s
        errors << "#{label} #{pair_label(pair)} right_image_sha256 does not exact-bind distinct_images"
      end

      same_sha = !left_sha.empty? && left_sha == right_sha
      if pair["same_image_exact_carry"] == true
        errors << "#{label} #{pair_label(pair)} exact-carry requires identical image SHA-256" unless same_sha
        errors << "#{label} #{pair_label(pair)} exact-carry result must be exact_carry" unless pair["declared_angle_difference_result"].to_s == "exact_carry"
      elsif same_sha
        errors << "#{label} #{pair_label(pair)} identical image SHA-256 is exact-carry, not a second production image"
      end

      errors << "#{label} #{pair_label(pair)} shot_scale_not_used_as_angle_proof must be true" unless pair["shot_scale_not_used_as_angle_proof"] == true
      errors << "#{label} #{pair_label(pair)} contextual_visual_review is missing" if pair["contextual_visual_review"].to_s.strip.empty?
      unless DECLARED_RESULTS.include?(pair["declared_angle_difference_result"].to_s)
        errors << "#{label} #{pair_label(pair)} declared_angle_difference_result is missing"
      end

      left_geo = pair["left_geometry_projection_sha256"].to_s
      left_geo = pair["left_geometry_value_sha256"].to_s if left_geo.empty?
      right_geo = pair["right_geometry_projection_sha256"].to_s
      right_geo = pair["right_geometry_value_sha256"].to_s if right_geo.empty?
      expected_left_geo = left["geometry_projection_sha256"].to_s
      expected_right_geo = right["geometry_projection_sha256"].to_s
      errors << "#{label} #{pair_label(pair)} left_geometry_projection_sha256 is missing or stale" unless left_geo == expected_left_geo && !left_geo.empty?
      errors << "#{label} #{pair_label(pair)} right_geometry_projection_sha256 is missing or stale" unless right_geo == expected_right_geo && !right_geo.empty?

      exception_errors = founder_exception_errors(pair["founder_exception"], pair, root)
      errors.concat(exception_errors)
      if pair["founder_exception"]
        errors << "#{label} #{pair_label(pair)} bound Founder exception must declare founder_lock_hold" unless pair["declared_angle_difference_result"].to_s == "founder_lock_hold"
        errors << "#{label} bound Founder exception cannot close camera_diversity_review as pass" unless parent_verdict.to_s == "hold"
      elsif pair["declared_angle_difference_result"].to_s == "founder_lock_hold"
        errors << "#{label} #{pair_label(pair)} founder_lock_hold requires an exact-bound Founder exception"
      end

      if pair["declared_angle_difference_result"].to_s == "same" && pair["same_image_exact_carry"] != true && parent_verdict.to_s == "pass"
        errors << "#{label} #{pair_label(pair)} model-authored same-angle pair cannot close as pass without a bound Founder exception HOLD"
      end
    end

    errors
  end
end
