# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    # Functions related to the SketchUp Tools.
    module ToolHelper
      # Activate a Ruby tool.
      #
      # @param tool_class [Class]
      #   A class implementing the abstract `Sketchup::Tool`.
      def self.activate(tool_class)
        Sketchup.active_model.select_tool(tool_class.new)
      end

      # Test if a Ruby tool is currently active.
      #
      # @param tool_class [Class]
      #   A class implementing the abstract `Sketchup::Tool`.
      #
      # @since SketchUp 2019
      def self.active?(tool_class)
        Sketchup.active_model.tools.active_tool.is_a?(tool_class)
      end

      # Create a command object for activating a tool.
      #
      # @param tool_class [Class]
      #   A class implementing the abstract `Sketchup::Tool`.
      # @param tool_name [String]
      # @param tool_description [String]
      #
      # @return [UI::Command]
      def self.create_command(tool_class, tool_name, tool_description)
        command = UI::Command.new(tool_name) { activate(tool_class) }
        command.tooltip = tool_name
        command.status_bar_text = tool_description
        # For SketchUp versions older than 2019, don't show tool's active state.
        # We'd need separate logic to track activation and de-activation.
        if Sketchup.version >= "19"
          command.set_validation_proc { active?(tool_class) ? MF_CHECKED : MF_ENABLED }
        end

        command
      end
    end
  end
end
