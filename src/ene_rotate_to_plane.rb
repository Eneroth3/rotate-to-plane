# frozen_string_literal: true

require "extensions.rb"

# Eneroth Extensions
module Eneroth
  # Eneroth Rotate To Plane
  module RotateToPlane
    path = __FILE__.dup
    path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)

    # Identifier for this extension.
    PLUGIN_ID = File.basename(path, ".*")

    # Root directory of this extension.
    PLUGIN_ROOT = File.join(File.dirname(path), PLUGIN_ID)

    # Extension object for this extension.
    EXTENSION = SketchupExtension.new(
      "Eneroth Rotate to Plane",
      File.join(PLUGIN_ROOT, "main")
    )

    EXTENSION.creator     = "Eneroth"
    EXTENSION.description = "Rotate point onto plane. Useful to lean a ladder against a wall or for paper pop-ups."
    EXTENSION.version     = "1.0.2"
    EXTENSION.copyright   = "2023, #{EXTENSION.creator}"
    Sketchup.register_extension(EXTENSION, true)
  end
end
