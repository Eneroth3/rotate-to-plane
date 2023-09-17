module Eneroth
  module RotateToPlane
    Sketchup.require "#{PLUGIN_ROOT}/tool"

    unless @loaded
      @loaded = true

      menu = UI.menu("Plugins")
      menu.add_item(EXTENSION.name) do
        tool = Eneroth::RotateToPlane::RotateToPlaneTool.new
        Sketchup.active_model.select_tool(tool)
      end
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

      # Use a timer to make call to method itself register to console.
      # Otherwise the user cannot use up arrow to repeat command.
      UI.start_timer(0) { SKETCHUP_CONSOLE.clear } if clear_console

      Sketchup.undo if undo

      nil
    end
  end
end
