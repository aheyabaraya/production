# frozen_string_literal: true

require "pathname"
require_relative "idol_front_planning_sequence_core_hold"

# Mechanical Local/Pairwise/Global presence for new Front Planning authoring.
# Frozen COLOR STAY v17 is skipped unless --admission-graph is set. This is not
# Front Planning v18 admission.
module IdolFrontPlanningLocalPairwiseGlobal
  HOLD_CODE = "local_pairwise_global_presence_missing"
  OWNER_HOLD_CODE = "local_pairwise_global_owner_mismatch"
  LOCAL_PAIRWISE_OWNER = "creative_development_director"
  GLOBAL_OWNER = "overall_director"

  module_function

  def skip_frozen_legacy?(path, admission_graph:)
    IdolFrontPlanningSequenceCoreHold.skip_frozen_legacy?(path, admission_graph: admission_graph)
  end

  def holds(document)
    graph = document["creative_review_graph"]
    unless graph.is_a?(Hash)
      return [{
        "code" => HOLD_CODE,
        "scope" => "creative_review_graph",
        "detail" => "new Front Planning must declare local, pairwise, and global review nodes"
      }]
    end

    rows = []
    %w[local pairwise global].each do |key|
      node = graph[key]
      unless node.is_a?(Hash) && node["present"] == true
        rows << {
          "code" => HOLD_CODE,
          "scope" => key,
          "detail" => "#{key} review node must be present"
        }
        next
      end

      expected = key == "global" ? GLOBAL_OWNER : LOCAL_PAIRWISE_OWNER
      next if node["owner_role"].to_s == expected

      rows << {
        "code" => OWNER_HOLD_CODE,
        "scope" => key,
        "detail" => "#{key} owner_role must be #{expected}"
      }
    end
    rows
  end
end
