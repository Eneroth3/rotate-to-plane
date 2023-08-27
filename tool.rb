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
def intersect_plane_circle(plane, center, radius, normal)
  line = Geom.intersect_plane_plane(plane, [center, normal])
  return unless line
  
  intersect_line_sphere(line, center, radius)
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
    @rotation_axis
    @start_point
    @target_plane
    @resulting_points
    
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
  def draw(view)
    if @input_point.valid?
      @input_point.draw(view)
      view.tooltip = @input_point.tooltip
    end
    
    case @stage
    when STAGE_PICK_ROTATION_AXIS
      # REVIEW: Style as selection or an infinite dotted line?
      # Or the former for this stage and latter for next stage?
      # Extract infinite line drawer that finds intersections to view frustrum?
      view.drawing_color = view.model.rendering_options["HighlightColor"]
      view.line_width = 3
      view.draw_line(*@rotation_axis) if @rotation_axis
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
      progress_stage unless view.model.selection.empty?
    when STAGE_PICK_ROTATION_AXIS
      progress_stage if @rotation_axis
      ### view.model.entities.add_cline(*@rotation_axis)
    when STAGE_PICK_START_POINT
      if @input_point.valid?
        progress_stage
        @start_point = @input_point.position
        @input_point.clear
        view.invalidate
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
      # Avoid actually selecting the edge as it may occur in several instances
      # of the component and look confusing.
      pick_helper = view.pick_helper
      pick_helper.do_pick(x, y)
      hovered = view.pick_helper.picked_edge
      
      @rotation_axis = nil
      if hovered
        pick_index = pick_helper.count.times.find { |i| pick_helper.leaf_at(i) == hovered }
        transformation = pick_helper.transformation_at(pick_index)
        @rotation_axis = hovered.line.map { |c| c.transform(transformation) }
        # HACK: Transfer length for visual height here. TODO: Take any scaling into account.
        @rotation_axis[1].length = hovered.length
      end
      view.invalidate
      # TODO: Handle mouse drag...
    when STAGE_PICK_START_POINT
      @input_point.pick(view, x, y)
      # Can't pick a rotation start point at the rotation axis.
      @input_point.clear if @input_point.position.on_line?(@rotation_axis)
      view.invalidate
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
  
  def update_statusbar
    texts = [
      "Pick entity to rotate.",
      "Pick rotation axis from edge, or hold and drag for custom axis.",
      "Pick rotation start point.",
      "Pick target plane from face, edge, or hold and drag for custom plane."
    ]
    
    Sketchup.status_text = texts[@stage]
  end
end

Sketchup.active_model.select_tool(RotateToPlaneTool.new)

=begin
# Select Circle/Arc and Face and run snippet.

# Typically work flow:
# 1. Draw a temporary face on the plane you want the paper's side/corner to intersect.
# 2. Draw a 2D arc around the rotation line, with the starting point at the paper's corner, to an arbitrary angle.
# 3. Select Arc and Face.
# 4. Run script.
# 5. Rotate using native Rotate tool.
# 6. Clean up help geometry.

model = Sketchup.active_model
face = model.selection.grep(Sketchup::Face).first
circle = model.selection.grep(Sketchup::Edge).first.curve

points = intersect_plane_circle(face.plane, circle.center, circle.radius, circle.normal)
points.each { |pt| model.active_entities.add_cpoint(pt) }
# TODO: Handle no intersection
=end


