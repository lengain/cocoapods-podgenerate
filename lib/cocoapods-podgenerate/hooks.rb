# frozen_string_literal: true

# [cocoapods-podgenerate]
# Hook registration for CocoaPods plugin system.
# Registers a :pre_install hook so patches are applied before the install flow.

Pod::HooksManager.register('cocoapods-podgenerate', :pre_install) do |_context|
  Pod::PodGenerate.activate
end
