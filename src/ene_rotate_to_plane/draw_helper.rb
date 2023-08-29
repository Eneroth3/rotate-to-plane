module Eneroth
  module RotateToPlane
    # Draws things to the screen during tool usage.
    module DrawHelper
      # REVIEW: Getting a lot of duplicated code for each new symbol to draw.
      # What if you want to draw same thing in screen space but faded
      # out for that X ray effect?
      # Maybe don't make any draw calls here but use it as helpers to calculate
      # the coordinates only? Or maybe go other way and

      # Points approximating the unit circle in X Y plane.
      CIRCLE_POINTS = 96.times.map do |i|
        t = 2 * Math::PI * i / 96.0
        Geom::Point3d.new(Math.cos(t), Math.sin(t), 0)
      end

      # Points making up a unit square in X Y plane.
      SQUARE_PONTS = [
        Geom::Point3d.new(0.5, 0.5, 0),
        Geom::Point3d.new(-0.5, 0.5, 0),
        Geom::Point3d.new(-0.5, -0.5, 0),
        Geom::Point3d.new(0.5, -0.5, 0)
      ]

      def self.draw_circle(view, center, normal, radius)
        transformation = transformation(center, normal, radius)
        corners = CIRCLE_POINTS.map { |pt| pt.transform(transformation) }
        view.draw(GL_LINE_LOOP, corners)
      end

      def self.draw_square(view, center, normal, side)
        transformation = transformation(center, normal, side)
        corners = SQUARE_PONTS.map { |pt| pt.transform(transformation) }
        view.draw(GL_LINE_LOOP, corners)
      end

      # REVIEW: Add SketchUp protractor

      # REVIEW: Make the logical pixel sized thingies be the normal ones and
      # have the long method name for the one in model scale?

      def self.draw_px_size_circle(view, center, normal, px_radius)
        radius = view.pixels_to_model(px_radius, center)
        draw_circle(view, center, normal, radius)
      end

      def self.draw_px_size_square(view, center, normal, px_side)
        side = view.pixels_to_model(px_side, center)
        draw_square(view, center, normal, side)
      end

      def self.set_color_from_line(view, line)
        view.set_color_from_line(line[0], line[0].offset(line[1]))
      end

      # REVIEW: Make overload taking an "up" vector, if the rotation matters.
      def self.transformation(center, normal, scale)
        Geom::Transformation.new(center, normal) *
        Geom::Transformation.scaling(scale)
      end
    end
  end
end
