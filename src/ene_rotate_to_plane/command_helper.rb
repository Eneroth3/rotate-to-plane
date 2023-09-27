# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    # Functions related to the SketchUp UI Command.
    module CommandHelper
      # Add icon to command.
      # Adds either SVG, PDF and PNG icons based on environment. Make sure to
      # include all files in the extension.
      #
      # @param command [UI::Command]
      # @param basepath [String] Path excluding the file extension.
      def self.add_icon(command, basepath)
        extension =
          if Sketchup.version.to_i > 15
            ".png"
          elsif Sketchup.platform == :platform_win
            ".svg"
          else
            ".pdf"
          end
        command.large_icon = command.small_icon = "#{basepath}#{extension}"
      end
    end
  end
end
