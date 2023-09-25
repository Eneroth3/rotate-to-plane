# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"
    Sketchup.require "#{PLUGIN_ROOT}/draw_helper"

    # Tool for rotating objects.
    class Tool
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

      # Distance in logical pixels needed between current mouse position and
      # mouse down position for it to count as a drag action. Non-zero to avoid
      # quick clicks before the cursor has fully stopped to be unintentionally
      # registered as drags.
      DRAG_THRESHOLD = 5

      # Create tool object.
      def initialize
        @rotation_axis = nil
        @start_point = nil
        @target_plane = nil
        @intersection_points = nil

        @stage = STAGE_PICK_OBJECT

        # Always drawn (if defined)
        @input_point = Sketchup::InputPoint.new
        # Used for drag vector input. Never drawn.
        @reference_input_point = Sketchup::InputPoint.new

        @mouse_position = nil

        # Used to identify hold-drag pattern used for custom line and plane inputs.
        @mouse_down = nil

        # Used to track the previous tool operation so it can be altered by
        # keyboard input.
        @previosly_modified_objects = nil
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
        @reference_input_point.draw(view) if @reference_input_point.valid?

        case @stage
        when STAGE_PICK_ROTATION_AXIS
          if @rotation_axis
            DrawHelper.set_color_from_vector(view, @rotation_axis[1])
            DrawHelper.draw_circle_px_size(view, *@rotation_axis, 50)
            if dragging_mouse?
              view.line_stipple = "."
              view.draw(GL_LINES, line_to_points(@rotation_axis))
              view.line_stipple = ""
            end
          end
        when STAGE_PICK_START_POINT
          if @input_point.valid?
            center = @input_point.position.project_to_line(@rotation_axis)
            DrawHelper.set_color_from_vector(view, @rotation_axis[1])
            radius = center.distance(@input_point.position)
            DrawHelper.draw_circle(view, center, @rotation_axis[1], radius)
          end
        when STAGE_PICK_TARGET_PLANE
          if @target_plane
            DrawHelper.set_color_from_vector(view, @target_plane[1])
            DrawHelper.draw_square_px_size(view, *@target_plane, 50)
          end
        end
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onCancel(_reason, view)
        reset_stage
        view.invalidate
      end

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
      def onLButtonDown(_flags, x, y, _view)
        @mouse_down = Geom::Point3d.new(x, y, 0)
        @reference_input_point.copy!(@input_point)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(_flags, _x, _y, view)
        @mouse_down = nil
        @reference_input_point.clear

        case @stage
        when STAGE_PICK_OBJECT
          unless view.model.selection.empty?
            # This is where the statusbar text stops mentioning Alt for changing
            # the direction of any previous rotation.
            @previosly_modified_objects = nil
            progress_stage
          end
        when STAGE_PICK_ROTATION_AXIS
          progress_stage if @rotation_axis
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
            @intersection_points = GeomHelper.intersect_plane_circle(@target_plane, center, normal, radius)
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
      def onMouseMove(_flags, x, y, view)
        @mouse_position = Geom::Point3d.new(x, y, 0)

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
          if dragging_mouse?
            # Special input that allows the user to select any direction in space.
            @input_point.pick(view, x, y, @reference_input_point)
            @rotation_axis = points_to_line(@reference_input_point.position, @input_point.position)
          else
            # Basic input that picks a rotational plane from the hovered entity.
            # Default to the hovered edge as this tool is specialized for paper
            # pop up models and we almost always want to rotate a piece of paper
            # around its edge.

            # REVIEW: Consider picking from inside face too, but that might
            # affect the scope of the tool to a more generic rotate tool and
            # lead to confusion why the tool even picks from edges.
            @rotation_axis = nil
            @input_point.pick(view, x, y)
            hovered = @input_point.edge
            if hovered
              @rotation_axis = [@input_point.position, hovered.line[1].transform(@input_point.transformation)]
            end
          end
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
          # REVIEW: Support empty space for ground plane?

          if @input_point.edge
            # Assume a vertical plane from edge.
            line = @input_point.edge.line.map { |c| c.transform(@input_point.transformation) }
            # Ignore vertical edges.
            unless line[1].parallel?(view.model.axes.zaxis)
              horizontal_tangent = line[1] * view.model.axes.zaxis
              @target_plane = [@input_point.position, horizontal_tangent]
            end
          end
          if !@target_plane && @input_point.face
            # FIXME: InputPoint.transformation returns a transformation that is
            # not for the face if the point is not on the face but floating on
            # top of it.
            # See https://github.com/Eneroth3/inputpoint-refinement-lib
            # Also, the position would be undesired in such case.
            @target_plane = [
              @input_point.position,
              GeomHelper.transform_normal(@input_point.face.normal, @input_point.transformation)
            ]
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

      def dragging_mouse?
        @mouse_down && @mouse_down.distance(@mouse_position) > DRAG_THRESHOLD
      end

      # TODO: Use these methods when possible

      def points_to_line(point1, point2)
        [point1, point2 - point1]
      end

      def line_to_points(line)
        [line[0], line[0].offset(line[1])]
      end

      def rotate_objects(view)
        view.model.start_operation("Rotate to Plane", true)

        angle = GeomHelper.angle_in_plane(@rotation_axis, @start_point, @intersection_points.first)
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
