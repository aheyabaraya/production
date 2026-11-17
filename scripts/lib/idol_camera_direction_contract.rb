# frozen_string_literal: true

# Shared deterministic token projection for stage-owned camera language.
# It translates already-authored values and never chooses creative truth.
# 01/02A/02B use still_prompt_sentence without temporal motion; 03V may use
# motion_prompt_sentence only after actual pixel inspection supplies the route.
module IdolCameraDirectionContract
  TOKEN_PHRASES = {
    "SS_MACRO" => "macro detail shot",
    "SS_ECU" => "extreme close-up",
    "SS_CU" => "close-up",
    "SS_MCU" => "medium close-up",
    "SS_MS" => "medium shot",
    "SS_MLS" => "medium-long shot",
    "SS_COWBOY" => "cowboy shot",
    "SS_FS" => "full-body shot",
    "SS_WS" => "wide shot",
    "SS_EWS" => "extreme-wide shot",
    "SS_EST" => "establishing shot",
    "SS_2SHOT" => "two-shot",
    "SS_GROUP" => "group shot",
    "H_FLOOR" => "floor-level",
    "H_KNEE" => "knee-height",
    "H_HIP" => "hip-height",
    "H_CHEST" => "chest-height",
    "H_EYE" => "eye-level",
    "H_HIGH" => "high camera",
    "H_OVERHEAD" => "overhead camera",
    "H_BIRD" => "high bird's-eye camera",
    "A_FRONT" => "frontal angle",
    "A_34" => "three-quarter angle",
    "A_PROFILE" => "profile angle",
    "A_BACK" => "rear angle",
    "A_OTS" => "over-the-shoulder angle",
    "A_LOW" => "low angle",
    "A_HIGH_OBLIQUE" => "high oblique angle",
    "A_TOPDOWN" => "top-down angle",
    "A_DUTCH" => "Dutch angle",
    "A_REFLECTION" => "reflection-mediated angle",
    "A_POV_ADJ" => "POV-adjacent angle",
    "M_HOLD_LOCK" => "locked camera hold",
    "M_HOLD_DRIFT" => "micro-drift camera hold",
    "M_PAN" => "camera pan",
    "M_TILT" => "camera tilt",
    "M_PEDESTAL" => "camera pedestal move",
    "M_PUSH" => "physical camera push-in",
    "M_PULL" => "physical camera pullback",
    "M_ZOOM" => "optical zoom",
    "M_PUNCH" => "short optical punch-in",
    "M_RECOIL" => "impact recoil and settle",
    "M_TRUCK_LATERAL" => "lateral trucking move",
    "M_TRACK" => "tracking move",
    "M_TRACK_LATERAL" => "lateral tracking move",
    "M_FOLLOW" => "front-or-back follow move",
    "M_ARC" => "partial curved arc move",
    "M_ORBIT" => "orbit around a stable anchor",
    "M_CRANE_UP" => "crane rise",
    "M_CRANE_DOWN" => "crane descent",
    "M_AXIS_DRIVE" => "depth-axis move",
    "M_FIELD_SWEEP" => "wide field sweep",
    "M_WHIP_PAN" => "whip pan",
    "M_WHIP_TILT" => "whip tilt",
    "M_ROLL" => "camera roll",
    "M_DOLLY_ZOOM" => "dolly zoom",
    "M_PARALLAX" => "foreground-parallax result",
    "M_RACK_FOCUS" => "rack-focus transfer",
    "R_TRIPOD_LOCK" => "tripod-locked support",
    "R_DOLLY" => "smooth dolly support",
    "R_JIB_CRANE" => "jib-or-crane support",
    "R_HANDHELD" => "handheld motion character",
    "R_SHOULDER" => "shoulder-mounted motion character",
    "R_STEADICAM" => "Steadicam motion character",
    "R_GIMBAL" => "gimbal-stabilized motion character",
    "R_DRONE_AERIAL" => "aerial drone motion character",
    "R_FPV" => "FPV flight motion character",
    "R_BODY_MOUNT" => "subject-mounted camera character",
    "V_STILL" => "still speed",
    "V_CREEP" => "creeping speed",
    "V_SLOW" => "slow speed",
    "V_MED" => "moderate speed",
    "V_BRISK" => "brisk speed",
    "V_FAST" => "fast speed",
    "V_IMPACT" => "single-impact speed",
    "E_CONSTANT" => "constant speed envelope",
    "E_EASE_IN" => "ease-in speed envelope",
    "E_EASE_OUT" => "ease-out speed envelope",
    "E_HIT_STOP" => "hit-and-stop speed envelope",
    "E_BREATH" => "breathing speed envelope",
    "E_STUTTER" => "stuttered speed envelope",
    "E_RAMP_UP" => "ramping-up speed envelope",
    "E_RAMP_DOWN" => "ramping-down speed envelope",
    "E_PULSE" => "pulsed speed envelope",
    "C_CENTER_LOCK" => "center-locked composition",
    "C_RULE_THIRDS" => "rule-of-thirds composition",
    "C_TRIANGLE" => "triangular composition",
    "C_FG_DOMINANT" => "foreground-dominant composition",
    "C_NEGATIVE_SPACE" => "negative-space composition",
    "C_FRAME_IN_FRAME" => "frame-within-frame composition",
    "C_LEADING_LINES" => "leading-line composition",
    "C_SYMMETRY" => "symmetrical composition",
    "C_DIAGONAL" => "diagonal composition",
    "C_TOPDOWN_GEOMETRY" => "top-down geometric composition",
    "C_SPLIT_FIELD" => "split-field composition",
    "C_STACK_DEPTH" => "stacked-depth composition",
    "C_TINY_IN_FIELD" => "small subject in a broad field",
    "C_CROP_PRESSURE" => "crop-pressure composition",
    "L_MACRO_SHALLOW" => "shallow macro lens feel",
    "L_PORTRAIT" => "portrait lens feel",
    "L_NORMAL" => "natural-perspective lens feel",
    "L_WIDE_NEAR" => "near-subject wide-lens feel",
    "L_LONG_COMPRESS" => "long-lens compression",
    "L_WIDE_FIELD" => "broad wide-field lens feel",
    "L_ULTRAWIDE_FISHEYE" => "ultrawide fisheye perspective",
    "L_ANAMORPHIC_WIDE" => "anamorphic wide-field character",
    "L_SPLIT_DIOPTER" => "split-diopter near-and-far focus",
    "L_TILT_SHIFT" => "tilt-shift focus-plane character",
    "T_MATCH_VECTOR" => "carried-vector match handoff"
  }.freeze

  STILL_AXIS_FIELDS = %w[
    camera_height shot_scale_family shot_scale_distance direction_angle
    depth_design subject_placement crop_negative_space composition_family
    lens_feel transition_family audio_story_job
  ].freeze

  MOTION_AXIS_FIELDS = %w[
    start_view movement_family movement_direction rig_character speed base_speed
    motion_envelope envelope depth_change reveal_target stop_trigger
    readability_reason edit_handoff
  ].freeze

  AXIS_FIELDS = (STILL_AXIS_FIELDS + MOTION_AXIS_FIELDS).uniq.freeze

  module_function

  def humanize(value)
    text = value.to_s.strip
    TOKEN_PHRASES.keys.sort_by { |token| -token.length }.each do |token|
      text = text.gsub(/(?<![A-Z0-9_])#{Regexp.escape(token)}(?![A-Z0-9_])/, TOKEN_PHRASES.fetch(token))
    end
    text
  end

  def still_prompt_axis_phrases(route_spec)
    shot_scale = route_spec["shot_scale_distance"].to_s.strip
    shot_scale = route_spec["shot_scale_family"] if shot_scale.empty?
    phrases = [
      "#{humanize(route_spec['camera_height'])} #{humanize(shot_scale)}, #{humanize(route_spec['direction_angle'])}",
      "depth: #{humanize(route_spec['depth_design'])}"
    ]
    placement = compact_text_values([route_spec["subject_placement"], route_spec["crop_negative_space"]]).join("; ")
    phrases << "frame: #{humanize(placement)}" unless placement.empty?
    spatial_read = compact_text_values([route_spec["composition_family"], route_spec["lens_feel"]]).map { |value| humanize(value) }
    phrases << spatial_read.join(" with ") unless spatial_read.empty?
    phrases << humanize(route_spec["transition_family"]) unless route_spec["transition_family"].to_s.strip.empty?
    phrases << "job: #{humanize(route_spec['audio_story_job'])}"
    phrases.map(&:strip).reject { |value| value.empty? || value.match?(/\A(?:depth|frame|job):\s*\z/) }
  end

  def prompt_axis_phrases(route_spec)
    still_prompt_axis_phrases(route_spec)
  end

  def prompt_sentence(route_spec)
    still_prompt_sentence(route_spec)
  end

  def still_prompt_sentence(route_spec)
    still_prompt_axis_phrases(route_spec).join(" | ")
  end

  def motion_prompt_axis_phrases(route_spec)
    speed_value = route_spec["speed"].to_s.strip
    speed_value = route_spec["base_speed"] if speed_value.empty?
    envelope_value = route_spec["motion_envelope"].to_s.strip
    envelope_value = route_spec["envelope"] if envelope_value.empty?
    motion = compact_text_values([
      route_spec["movement_family"],
      route_spec["movement_direction"],
      route_spec["rig_character"]
    ]).map { |value| humanize(value) }.join(", ")
    pace = compact_text_values([speed_value, envelope_value]).map { |value| humanize(value) }.join(", ")
    phrases = []
    phrases << "start view: #{humanize(route_spec['start_view'])}" unless route_spec["start_view"].to_s.strip.empty?
    phrases << "camera route: #{motion}" unless motion.empty?
    phrases << "pace: #{pace}" unless pace.empty?
    phrases << "depth change: #{humanize(route_spec['depth_change'])}" unless route_spec["depth_change"].to_s.strip.empty?
    phrases << "reveal: #{humanize(route_spec['reveal_target'])}" unless route_spec["reveal_target"].to_s.strip.empty?
    phrases << "stop: #{humanize(route_spec['stop_trigger'])}" unless route_spec["stop_trigger"].to_s.strip.empty?
    phrases << "readability: #{humanize(route_spec['readability_reason'])}" unless route_spec["readability_reason"].to_s.strip.empty?
    phrases << "edit handoff: #{humanize(route_spec['edit_handoff'])}" unless route_spec["edit_handoff"].to_s.strip.empty?
    phrases
  end

  def motion_prompt_sentence(route_spec)
    motion_prompt_axis_phrases(route_spec).join(" | ")
  end

  def still_camera_spec_from_02a_cut(cut)
    cut = {} unless cut.is_a?(Hash)
    return cut["still_camera_spec"] if cut["still_camera_spec"].is_a?(Hash)

    imported = cut["imported_core"]
    return imported["camera"] if imported.is_a?(Hash) && imported["camera"].is_a?(Hash)

    nil
  end

  def compact_text_values(values)
    Array(values).flatten.each_with_object([]) do |value, result|
      text = value.to_s.strip
      next if text.empty?

      normalized = text.downcase.gsub(/\s+/, " ")
      next if result.any? { |existing| existing.downcase.gsub(/\s+/, " ").include?(normalized) }

      result.delete_if { |existing| normalized.include?(existing.downcase.gsub(/\s+/, " ")) }
      result << text
    end
  end

  def local_camera_realization(cut, shot_lock: nil)
    chain = cut.is_a?(Hash) && cut["director_chain"].is_a?(Hash) ? cut["director_chain"] : {}
    visual = cut.is_a?(Hash) && cut["visual_frame"].is_a?(Hash) ? cut["visual_frame"] : {}
    values = [
      chain.dig("must_show", "camera"),
      visual["camera_treatment"],
      visual["camera"]
    ]
    values << shot_lock["camera_treatment"] if shot_lock.is_a?(Hash)
    compact_text_values(values).map { |value| humanize(value) }.join(" | ")
  end

  def merged_prompt_sentence(route_spec, local_realization)
    governing = still_prompt_sentence(route_spec)
    local = humanize(local_realization)
    return governing if local.strip.empty?

    "Passed still-camera basis: #{governing} | Local still realization (adds placement, crop, depth, motion-ready room, or continuity detail without authoring temporal motion): #{local}"
  end
end
