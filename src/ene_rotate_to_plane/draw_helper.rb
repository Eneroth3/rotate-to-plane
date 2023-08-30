module Eneroth
  module RotateToPlane
    # Draws things to the screen during tool usage.
    module DrawHelper
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

      # Draw a circle to the view.
      #
      # @param view [Sketchup::View]
      # @param center [Geom::Point3d]
      # @param normal [Geom::Vector3d]
      # @param radius [Length]
      def self.draw_circle(view, center, normal, radius)
        transformation = transformation(center, normal, radius)
        corners = CIRCLE_POINTS.map { |pt| pt.transform(transformation) }
        view.draw(GL_LINE_LOOP, corners)
      end

      # Draw a circle to the view, with the radius defined in logical pixels.
      #
      # @param view [Sketchup::View]
      # @param center [Geom::Point3d]
      # @param normal [Geom::Vector3d]
      # @param px_radius [Numeric]
      def self.draw_circle_px_size(view, center, normal, px_radius)
        radius = view.pixels_to_model(px_radius, center)
        draw_circle(view, center, normal, radius)
      end

      # Draw a square to the view.
      #
      # @param view [Sketchup::View]
      # @param center [Geom::Point3d]
      # @param normal [Geom::Vector3d]
      # @param side [Length]
      def self.draw_square(view, center, normal, side)
        transformation = transformation(center, normal, side)
        corners = SQUARE_PONTS.map { |pt| pt.transform(transformation) }
        view.draw(GL_LINE_LOOP, corners)
      end

      # Draw a square to the view, with the side defined in logical pixels.
      #
      # @param view [Sketchup::View]
      # @param center [Geom::Point3d]
      # @param normal [Geom::Vector3d]
      # @param side [Length]
      def self.draw_square_px_size(view, center, normal, px_side)
        side = view.pixels_to_model(px_side, center)
        draw_square(view, center, normal, side)
      end

      # Set the view drawing color the model axis color from a vector.
      #
      # @param view [Sketchup::View]
      # @param vector [Geom::Vector3d]
      def self.set_color_from_vector(view, vector)
        view.set_color_from_line(ORIGIN, ORIGIN.offset(vector))
      end

      # Calculate transformation moving a symbol from the X Y plane into the
      # 3d model space.
      #
      # @param center [Geom::Point3d]
      # @param normal [Geom::Vector3d]
      # @param scale [Numeric]
      #   Use 'Sketchup::view#pixels_to_model' if the original coordinates are
      #   in logical pixel space.
      #
      # @return [Geom::Transformation]
      def self.transformation(center, normal, scale)
        Geom::Transformation.new(center, normal) *
        Geom::Transformation.scaling(scale)
      end
    end
  end
end
