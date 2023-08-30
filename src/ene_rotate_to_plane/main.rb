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

        # Used to track the previous tool operation so it can be altered by
        # keyboard input.
        @previosly_modified_objects
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

        return unless key == VK_ALT
        return unless @stage == 0 && @previosly_modified_objects

        rotate_to_other_solution(view)

        # Return true to intercept SketchUp's key handling and not move focus to
        # the menu.
        true
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onLButtonDown(_flags, _x, _y, _view)
        @mouse_down = true # TODO: If not in use, remove this.
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(_flags, _x, _y, view)
        @mouse_down = false

        case @stage
        when STAGE_PICK_OBJECT
          unless view.model.selection.empty?
            # This is where the statusbar text stops mentioning Alt for changing
            # the direction of any previous rotation.
            @previosly_modified_objects = nil
            progress_stage
          end
        when STAGE_PICK_ROTATION_AXIS
          if @rotation_axis
            progress_stage
          end
        when STAGE_PICK_START_POINT
          if @input_point.valid?
            @start_point = @input_point.position
            progress_stage
          end
        when STAGE_PICK_TARGET_PLANE
          if @target_plane
            center = @start_point.project_to_line(@rotation_axis)
            radius = center.distance(@start_point)
            normal = @rotation_axis[1]
            @intersection_points = MathHelper.intersect_plane_circle(@target_plane, center, radius, normal)
            if @intersection_points
              # By default fold the direction closest to where the user placed the target.
              @intersection_points = @intersection_points.sort_by { |pt| pt.distance(@target_plane[0]) }
              rotate_objects(view)
              reset_stage
            else
              UI.messagebox("Can't reach plane")
            end
          end
        end
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onMouseMove(flags, x, y, view)
        case @stage
        when STAGE_PICK_OBJECT
          view.model.selection.clear
          pick_helper = view.pick_helper
          pick_helper.do_pick(x, y)
          hovered = view.pick_helper.best_picked
          # PickHelper can pick up the modeling axes.
          hovered = nil if hovered.is_a?(Sketchup::Axes)
          view.model.selection.add(hovered) if hovered
        when STAGE_PICK_ROTATION_AXIS
          @rotation_axis = nil
          @input_point.pick(view, x, y)
          # REVIEW: Consider supporting point on face and empty space too.
          # Would make tool more open but maybe more confusing in my use case.
          hovered = @input_point.edge
          if hovered
            @rotation_axis = [@input_point.position, hovered.line[1].transform(@input_point.transformation)]
          end
          # REVIEW: Consider adding mouse drag support for any custom plane.
          # TODO: Or otherwise remove it from the statusbar text.
        when STAGE_PICK_START_POINT
          @input_point.pick(view, x, y)
          # Can't pick a rotation start point at the rotation axis.
          @input_point.clear if @input_point.position.on_line?(@rotation_axis)
          # REVIEW: Consider only allowing input points within the selection.
          # Would make tool make tool more intuitive in my use case but a bit
          # more limited.
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
          # REVIEW: Consider adding mouse drag support for any custom plane.
          # TODO: Or otherwise remove it from the statusbar text.
        end
        view.invalidate
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
        @input_point.clear
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
        texts[0] += " Alt = Alternate fold direction. " if @previosly_modified_objects

        Sketchup.status_text = texts[@stage]
      end

      def rotate_objects(view)
        view.model.start_operation("Rotate to Plane")

        angle = MathHelper.angle_in_plane(@rotation_axis, @start_point, @intersection_points.first)
        transformation = Geom::Transformation.rotation(*@rotation_axis, angle)
        view.model.active_entities.transform_entities(transformation, view.model.selection)

        view.model.commit_operation

        @previosly_modified_objects = view.model.selection.to_a
      end

      # Change previously made rotation to go other direction.
      def rotate_to_other_solution(view)
        view.model.selection.clear
        view.model.selection.add(@previosly_modified_objects)
        @intersection_points.rotate!
        Sketchup.undo
        rotate_objects(view)
      end
    end
  end
end

### Sketchup.active_model.select_tool(Eneroth::RotateToPlane::RotateToPlaneTool.new)
