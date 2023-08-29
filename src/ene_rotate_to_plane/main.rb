module Eneroth
  module RotateToPlane
    Sketchup.require "#{PLUGIN_ROOT}/math_helper"
    Sketchup.require "#{PLUGIN_ROOT}/draw_helper"

    # Tool for rotating objects.
    class RotateToPlaneTool
      # REVIEW: Can we abstract tool stages, code each of them in one place and not
      # have them all intermingled?
      # Delegate all tool interface calls to separate classes, instead of case/when?

      # Pick object (any entity, or pre-selection)
      STAGE_PICK_OBJECT = 0
      # Pick rotation axis (click edge, press and drag for custom vector)
      STAGE_PICK_ROTATION_AXIS = 1
      # Pick start point (using InputPoint)
      STAGE_PICK_START_POINT = 2
      # Pick target plane (face, vertical plane from edge, press and drag for custom plane)
      STAGE_PICK_TARGET_PLANE = 3

      def initialize
        @rotation_axis
        @start_point
        @target_plane
        @intersection_points

        @stage = STAGE_PICK_OBJECT

        # Always drawn (if defined)
        @input_point = Sketchup::InputPoint.new
        # Used for drag vector input. Never drawn.
        @reference_input_point = Sketchup::InputPoint.new

        # Used to identify hold-drag pattern used for custom line and plane inputs.
        @mouse_down
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def activate
        # Skip selection stage if there is a pre-selection.
        unless Sketchup.active_model.selection.empty?
          @stage = STAGE_PICK_ROTATION_AXIS
        end

        update_statusbar
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def deactivate(view)
        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def draw(view)
        # Always draw the input point if valid.
        # Clear it in any tool state that's not using it.
        if @input_point.valid?
          @input_point.draw(view)
          view.tooltip = @input_point.tooltip
        end

        case @stage
        when STAGE_PICK_ROTATION_AXIS
          if @rotation_axis
            DrawHelper.set_color_from_line(view, @rotation_axis)
            DrawHelper.draw_px_size_circle(view, *@rotation_axis, 50)
          end
        when STAGE_PICK_START_POINT
          if @input_point.valid?
            center = @input_point.position.project_to_line(@rotation_axis)
            DrawHelper.set_color_from_line(view, @rotation_axis)
            radius = center.distance(@input_point.position)
            DrawHelper.draw_circle(view, center, @rotation_axis[1], radius)
            # REVIEW: Draw this circle in the next tool stage too
          end
        when STAGE_PICK_TARGET_PLANE
          if @target_plane
            DrawHelper.set_color_from_line(view, @target_plane)
            DrawHelper.draw_px_size_square(view, *@target_plane, 50)
          end
        end
      end

      # TODO: Add onCancel

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onKeyDown(key, _repeat, _flags, view)
        # Allow changing what direction objects flips after having made the operation.

        # REVIEW: Communicate with live preview and base direction on where
        # model is hovered instead of arbitrary order to solutions?
        # Alt key not communicated n statusbar text!

        return unless key == VK_ALT
        return unless @stage == 0 && @intersection_points

        rotate_to_other_solution(view)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onLButtonDown(_flags, _x, _y, _view)
        @mouse_down = true
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(_flags, _x, _y, view)
        @mouse_down = false

        case @stage
        when STAGE_PICK_OBJECT
          unless view.model.selection.empty?
            progress_stage
          end
        when STAGE_PICK_ROTATION_AXIS
          if @rotation_axis
            ### view.model.entities.add_cline(*@rotation_axis)
            progress_stage
            @input_point.clear
            view.invalidate
          end
        when STAGE_PICK_START_POINT
          if @input_point.valid?
            progress_stage
            @start_point = @input_point.position
            @input_point.clear
            view.invalidate
          end
        when STAGE_PICK_TARGET_PLANE
          if @target_plane
            ### view.model.entities.add_circle(*@target_plane, 1, 12)
            # REVIEW: Calculate in mouse move already to preview result?
            center = @start_point.project_to_line(@rotation_axis)
            radius = center.distance(@start_point)
            normal = @rotation_axis[1]
            ### view.model.entities.add_circle(center, normal, radius, 12)
            @intersection_points = MathHelper.intersect_plane_circle(@target_plane, center, radius, normal)

            if @intersection_points
              rotate_objects(view)
              reset_stage
            else
              UI.messagebox("Can't reach plane")
            end
          end
        end

        update_statusbar
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onMouseMove(flags, x, y, view)
        case @stage
        when STAGE_PICK_OBJECT
          # REVIEW: Extract generic hover picky thingy, where you set up the allowed
          # entity on creation?
          view.model.selection.clear
          pick_helper = view.pick_helper
          pick_helper.do_pick(x, y)
          hovered = view.pick_helper.best_picked
          view.model.selection.add(hovered) if hovered
        when STAGE_PICK_ROTATION_AXIS
          @rotation_axis = nil
          @input_point.pick(view, x, y)
          # TODO: Support face and empty space too.
          hovered = @input_point.edge
          if hovered
            @rotation_axis = [@input_point.position, hovered.line[1].transform(@input_point.transformation)]
          end
          # TODO: Handle mouse drag...
          view.invalidate
        when STAGE_PICK_START_POINT
          @input_point.pick(view, x, y)
          # Can't pick a rotation start point at the rotation axis.
          @input_point.clear if @input_point.position.on_line?(@rotation_axis)
          view.invalidate
        when STAGE_PICK_TARGET_PLANE
          @target_plane = nil
          @input_point.pick(view, x, y)
          # TODO: Support empty space for ground plane?
          hovered = @input_point.edge
          hovered = @input_point.face unless hovered
          if hovered.is_a?(Sketchup::Face)
            # FIXME: InputPoint.transformation returns a transformation that is
            # not for the face if the point is not on the face but floating on
            # top of it.
            # See https://github.com/Eneroth3/inputpoint-refinement-lib
            # Also, the position would be undesired in such case.
            @target_plane = [@input_point.position, hovered.normal.transform(@input_point.transformation)]
          elsif hovered.is_a?(Sketchup::Edge)
            # Assume a vertical plane from edge.
            line = hovered.line.map { |c| c.transform(@input_point.transformation) }
            # REVIEW: Use drawing axes, not global axes.
            # TODO: Ignore vertical edges.
            horizontal_tangent = line[1] * Z_AXIS
            @target_plane = [@input_point.position, horizontal_tangent]
          end
          # FIXME: Now rotation has different angle and I don't know why.
          # TODO: Handle mouse drag...
          view.invalidate # REVIEW: Move out of case?
        end
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def resume(view)
        view.invalidate
        update_statusbar
      end

      private

      def progress_stage
        @stage += 1
        @input_point.clear # TODO: Clear obsolete calls elsewhere
        update_statusbar
      end

      def reset_stage
        @stage = 0
        @input_point.clear
        update_statusbar
      end

      def update_statusbar
        texts = [
          "Pick entity to rotate.",
          "Pick rotation axis from edge, or hold and drag for custom axis.",
          "Pick rotation start point.",
          "Pick target plane from face, edge, or hold and drag for custom plane."
        ]

        Sketchup.status_text = texts[@stage]
      end

      def rotate_objects(view)
        view.model.start_operation("Rotate to Plane")

        angle = MathHelper.angle_in_plane(@rotation_axis, @start_point, @intersection_points.first)
        transformation = Geom::Transformation.rotation(*@rotation_axis, angle)
        view.model.active_entities.transform_entities(transformation, view.model.selection)

        view.model.commit_operation
      end

      # Change previously made rotation to go other direction.
      def rotate_to_other_solution(view)
        @intersection_points.rotate!
        Sketchup.undo
        rotate_objects(view)
      end
    end
  end
end

### Sketchup.active_model.select_tool(Eneroth::RotateToPlane::RotateToPlaneTool.new)
