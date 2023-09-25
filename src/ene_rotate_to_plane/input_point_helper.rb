# frozen_string_literal: true

module Eneroth
  module RotateToPlane
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"

    # Functions related to the SketchUp InputPoint.
    module InputPointHelper
      # Get model normal vector from screen coordinates.
      #
      # `Sketchup::InputPoint.transformation` and `Sketchup::InputPoint.face`
      # cannot be reliably used together as the input point may get its position
      # from an edge in another group or component than the best picked face.
      def self.normal(view, x, y)
        # It bugs me that we can't pass an InputPoint here and extract either
        # its internal pick helper or the screen space coordinates that was
        # passed to it :( .
        # REVIEW: This method technically uses no inference and could be in a
        # "PickHelperHelper" module, but since it concerns geometry/coordinates
        # and not entities/selection, it feels like an InputPoint related
        # method.

        ph = view.pick_helper(x, y)
        face = ph.picked_face
        return view.model.axes.zaxis unless face

        index = ph.count.times.find { |i| ph.leaf_at(i) == face }
        transformation = index ? ph.transformation_at(index) : IDENTITY

        GeomHelper.transform_normal(face.normal, transformation)
      end
    end
  end
end
