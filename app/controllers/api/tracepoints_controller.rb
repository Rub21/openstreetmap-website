# frozen_string_literal: true

module Api
  class TracepointsController < ApiController
    authorize_resource

    # Get an XML response containing a list of tracepoints that have been uploaded
    # within the specified bounding box. To get the next batch of points, follow
    # the URL given in the Link header of the response.
    def index
      # Figure out the bbox
      # check boundary is sane and area within defined
      # see /config/application.yml
      begin
        raise OSM::APIBadUserInput, "The parameter bbox is required" unless params[:bbox]

        bbox = BoundingBox.from_bbox_params(params)
        bbox.check_boundaries
        bbox.check_size
      rescue StandardError => e
        report_error(e.message)
        return
      end

      per_page = Settings.tracepoints_per_page

      if params[:page].blank?
        after = nil

        if params[:cursor]
          begin
            after = parse_cursor(params[:cursor])
          rescue ArgumentError, TypeError
            report_error("The cursor parameter is invalid")
            return
          end
        end

        # One extra point tells if there is a next page.
        points = GpxTrack.points_in_bbox(bbox, :limit => per_page + 1, :after => after)
        @points = points.first(per_page)

        if points.size > per_page
          next_url = api_tracepoints_url(:bbox => params[:bbox], :cursor => next_cursor(@points.last))
          response.headers["Link"] = "<#{next_url}>; rel=\"next\""
        end
      else
        page = params[:page].to_i

        unless page >= 0
          report_error("Page number must be greater than or equal to 0")
          return
        end

        @points = GpxTrack.points_in_bbox(bbox, :limit => per_page, :offset => page * per_page)
      end

      response.headers["Content-Disposition"] = "attachment; filename=\"tracks.gpx\""

      render :formats => [:gpx]
    end

    private

    # Cursor: gpx_id|trackid|segment|path of the last point of the previous page.
    def parse_cursor(cursor)
      parts = Base64.urlsafe_decode64(cursor).split("|")
      raise ArgumentError, "cursor needs four parts" unless parts.size == 4

      parts.map { |part| Integer(part) }
    end

    def next_cursor(point)
      Base64.urlsafe_encode64("#{point.gpx_id}|#{point.trackid}|#{point.segment}|#{point.path}", :padding => false)
    end
  end
end
