# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    # Various lierar algebra thingies not present in the Ruby API Geom module.
    module MathHelper
      # Calculate intersections between line and sphere.
      #
      # @param line [Array(Geom::Point3d, Geom::Vector3d)]
      # @param center [Geom::Point3d]
      # @param radius [Length]
      #
      # @return [Array(Geom::Point3d, Geom::Point3d), nil]
      def self.intersect_line_sphere(line, center, radius)
        # Taken from Eneroth 3D Rotate.

        origin = line[0]
        vector = line[1].normalize

        # Calculate distance from line's start along line to intersections
        term1 = -(vector % (origin - center))
        term2_squared =
          (vector % (origin - center))**2 -
          ((origin - center) % (origin - center)) + radius**2
        return if term2_squared < 0

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
      # @param normal [Geom::Vector3d]
      # @param radius [Length]
      #
      # @return [Array(Geom::Point3d, Geom::Point3d), nil]
      def self.intersect_plane_circle(plane, center, normal, radius)
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
      def self.angle_in_plane(axis, point1, point2)
        # Based on method from Eneroth 3D Rotate.
        # REVIEW: Have nicer method in Solar North that can be used.

        point1 = point1.project_to_plane(axis)
        point2 = point2.project_to_plane(axis)
        vector1 = point1 - axis[0]
        vector2 = point2 - axis[0]

        angle = vector1.angle_between(vector2)

        vector1 * vector2 % axis[1] > 0 ? angle : -angle
      end

      # When applying a sheared transformation to a normal vector, it no longer
      # stays perpendicular to its plane. This method transforms the normal
      # vector with the shearing in mind.
      #
      # @param normal [Geom::Vector3d]
      # @param transformation [Geom::Transformation]
      #
      # @return [Geom::Vector3d]
      def self.transform_normal(normal, transformation)
        tangent, bi_tangent = normal.axes
        tangent.transform!(transformation)
        bi_tangent.transform!(transformation)

        tangent * bi_tangent
      end
    end
  end
end
