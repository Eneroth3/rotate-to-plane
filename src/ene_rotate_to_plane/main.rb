# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    Sketchup.require "#{PLUGIN_ROOT}/tool"
    Sketchup.require "#{PLUGIN_ROOT}/tool_helper"
    Sketchup.require "#{PLUGIN_ROOT}/command_helper"

    unless @loaded
      @loaded = true

      command = ToolHelper.create_command(Tool, EXTENSION.name, EXTENSION.description)
      CommandHelper.add_icon(command, "#{PLUGIN_ROOT}/icons/rotate_to_plane")

      toolbar = UI::Toolbar.new(EXTENSION.name)
      toolbar.add_item(command)
      toolbar.restore

      menu = UI.menu("Plugins")
      menu.add_item(command)
    end

    # Reload extension.
    #
    # @param clear_console [Boolean] Whether console should be cleared.
    # @param undo [Boolean] Whether last operation should be undone.
    #
    # @return [void]
    def self.reload(clear_console = true, undo = false)
      # Hide warnings for already defined constants.
      verbose = $VERBOSE
      $VERBOSE = nil
      Dir.glob(File.join(PLUGIN_ROOT, "**/*.{rb,rbe}")).each { |f| load(f) }
      $VERBOSE = verbose

      # HACK: Use a timer to make call to method itself register to console.
      # Otherwise the user cannot use up arrow to repeat command.
      UI.start_timer(0) { SKETCHUP_CONSOLE.clear } if clear_console

      Sketchup.undo if undo

      nil
    end
  end
end
