# Rotate object to place point perfectly on a plane.
# This is an inference ("On Radius") that's missing in the native Rotate tool.
# Useful e.g. for making paper popup models.

# TODO: Propose adding this snap to Rotate, Arc and Pie tools.

# Calculate intersections between line and sphere.
#
# @param line [Array(Geom::Point3d, Geom::Vector3d)]
# @param center [Geom::Point3d]
# @param Length
#
# @return [Array(Geom::Point3d, Geom::Point3d), nil]
def intersect_line_sphere(line, center, radius)
  # Taken from Eneroth 3D Rotate.
  
  origin = line[0]
  vector = line[1].normalize
  
  # Calculate distance from line's start along line to intersections
  term1 = -(vector % (origin - center))
  term2_squared =
    (vector % (origin - center))**2 -
    ((origin - center) % (origin - center)) + radius**2
  return if(term2_squared < 0)
    
  term2 = Math.sqrt(term2_squared)
  # REVIEW: Return just one point if term2 is 0 (line tangents sphere)?
  
  [
    origin.offset(vector, term1 + term2),
    origin.offset(vector, term1 - term2)
  ]
end

# Calculate intersections between plane and a circle.
#
# @param plane [Array(Geom::Point3d, Geom::Vector3d), Array(Float, Float, Float, Float)]
# @param center [Geom::Point3d]
# @param radius [Length]
# @param normal [Geom::Vector3d]
#
# @return [Array(Geom::Point3d, Geom::Point3d), nil]
def intersect_plane_circle(plane, center, radius, normal) # REVIEW: Harmonize argument order with add_circle
  line = Geom.intersect_plane_plane(plane, [center, normal])
  return unless line
  
  intersect_line_sphere(line, center, radius)
end

# Calculate angle between two points, as seen along an axis.
# Can return negative angles unlike Ruby APIs Vector3d.angleBetween method
#
# @param axis [Array(Geom::Point3d, Geom::Vector3d)]
# @param point1 [Geom::Point3d]
# @param point2 [Geom::Point3d]
#
# @return [Float] Angle in radians.
def angle_in_plane(axis, point1, point2)
  # Based on method from Eneroth 3D Rotate.
  
  point1 = point1.project_to_plane(axis)
  point2 = point2.project_to_plane(axis)
  vector1 = point1 - axis[0]
  vector2 = point2 - axis[0]
  
  angle = vector1.angle_between(vector2)
  
  vector1 * vector2 % axis[1] > 0 ? angle : -angle
end

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
    @objects
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
      @objects = Sketchup.active_model.selection.to_a
    end
    
    update_statusbar
  end
  
  # @api
  # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
  def deactivate(view)
    # REVIEW: Not needed if we don't use selection to preview stuff.
    view.model.selection.clear
  end
  
  # @api
  # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
  def draw(view)
    if @input_point.valid?
      @input_point.draw(view)
      view.tooltip = @input_point.tooltip
    end
  end
  
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
        @objects = view.model.selection.to_a
      end
    when STAGE_PICK_ROTATION_AXIS
      ### view.model.entities.add_cline(*@rotation_axis)
      progress_stage if @rotation_axis
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
        @intersection_points = intersect_plane_circle(@target_plane, center, radius, normal)
        
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
      # REVIEW: May be better to just draw than select here.
      # Now seeing duplications across component instances.
      # Also keeps selection to the thing we are moving. Better UX and can remove tracking of @objects.
      view.model.selection.clear
      pick_helper = view.pick_helper
      pick_helper.do_pick(x, y)
      hovered = view.pick_helper.picked_edge
      view.model.selection.add(hovered)if hovered
      
      @rotation_axis = nil
      if hovered
        pick_index = pick_helper.count.times.find { |i| pick_helper.leaf_at(i) == hovered }
        transformation = pick_helper.transformation_at(pick_index)
        @rotation_axis = hovered.line.map { |c| c.transform(transformation) }
      end
      # TODO: Handle mouse drag...
    when STAGE_PICK_START_POINT
      @input_point.pick(view, x, y)
      # Can't pick a rotation start point at the rotation axis.
      @input_point.clear if @input_point.position.on_line?(@rotation_axis)
      view.invalidate
    when STAGE_PICK_TARGET_PLANE
      view.model.selection.clear
      pick_helper = view.pick_helper
      pick_helper.do_pick(x, y)
      hovered = view.pick_helper.picked_edge
      hovered = view.pick_helper.picked_face unless hovered
      view.model.selection.add(hovered)if hovered
      
      # TODO: Preview plane? Or just preview what the rotation would be?
      @target_plane = nil
      if hovered.is_a?(Sketchup::Face)
        pick_index = pick_helper.count.times.find { |i| pick_helper.leaf_at(i) == hovered }
        transformation = pick_helper.transformation_at(pick_index)
        @target_plane = [hovered.vertices.first.position, hovered.normal].map { |c| c.transform(transformation) }
      elsif hovered.is_a?(Sketchup::Edge)
        # Assume a vertical plane from edge.
        pick_index = pick_helper.count.times.find { |i| pick_helper.leaf_at(i) == hovered }
        transformation = pick_helper.transformation_at(pick_index)
        line = hovered.line.map { |c| c.transform(transformation) }
        # TODO: Use drawing axes, not global axes.
        horizontal_tangent = line[1] * Z_AXIS
        @target_plane = [line[0], horizontal_tangent]
      end
      # TODO: Handle mouse drag...
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
    update_statusbar
  end
  
  def reset_stage
    @stage = 0
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
    
    angle = angle_in_plane(@rotation_axis, @start_point, @intersection_points.first)
    transformation = Geom::Transformation.rotation(*@rotation_axis, angle)
    view.model.active_entities.transform_entities(transformation, @objects)
    
    view.model.commit_operation
  end
  
  # TODO: Press TAB to swap what point rotation is towards
  def rotate_to_other_point(view)
    @intersection_points.rotate
    view.model.undo
    rotate_objects(view)
  end
end

Sketchup.active_model.select_tool(RotateToPlaneTool.new)
