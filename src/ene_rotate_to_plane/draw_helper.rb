module Eneroth
  module RotateToPlane
    # Draws things to the screen during tool usage.
    module DrawHelper
      # REVIEW: What if you want to draw same thing in screen space but faded
      # out for that X ray effect, or draw a symbol other than a circle to a
      # given pixel size?
      # Maybe don't make any draw calls here but use it as helpers to calculate
      # the coordinates only?
    
      # Points approximating the unit circle in X Y plane.
      CIRCLE_POINTS = 96.times.map do |i|
        t = 2 * Math::PI * i / 96.0
        Geom::Point3d.new(Math.cos(t), Math.sin(t), 0)
      end
      
      def self.draw_circle(view, center, normal, radius)
        transformation =
          Geom::Transformation.new(center, normal) *
          Geom::Transformation.scaling(radius)
        corners = CIRCLE_POINTS.map { |pt| pt.transform(transformation) }
        view.draw(GL_LINE_LOOP, corners)
      end
      
      def self.draw_px_size_circle(view, center, normal, px_radius)
        radius = view.pixels_to_model(px_radius, center)
        draw_circle(view, center, normal, radius)
      end
      
      def self.set_color_from_line(view, line)
        view.set_color_from_line(line[0], line[0].offset(line[1]))
      end
    end
  end
end
