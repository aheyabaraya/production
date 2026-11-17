# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class IdolMvDirectorContextualCameraIntentTest < Minitest::Test
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path
  DIRECTOR_SKILL = ROOT.join("skills", "idol-mv-director", "SKILL.md")
  AUTHORING_DETAIL = ROOT.join("skills", "idol-mv-director", "references", "01-bundle-authoring-detail.md")
  INTEGRATION_MODULE = ROOT.join("skills", "idol-mv-director", "modules", "integration.md")

  def test_contextual_camera_intent_is_required_without_forcing_variety
    skill = DIRECTOR_SKILL.read
    detail = AUTHORING_DETAIL.read
    integration = INTEGRATION_MODULE.read

    assert_includes skill, "`modules/camera-coverage-vocabulary.md`"
    assert_includes skill, "`modules/integration.md` as the required final pass"
    assert_includes skill, "repeated and changed views both state what they preserve and newly"
    assert_includes skill, "any intentional recurrence states what changes"
    refute_match(/still camera is concrete and varied for the song/i, skill)
    refute_match(/nonrepetitive screen-branch opportunities/i, skill)

    assert_includes detail, "intentional use of"
    assert_includes detail, "recurrence or variation"
    assert_includes integration, "Do not vary or repeat them by default."
    assert_match(/Preserve an\s+exact recurrence/, integration)
    assert_includes integration, "Variation is valid only when it creates a"
  end
end
