# frozen_string_literal: true

require "test_helper"

module Api
  class TracepointsControllerTest < ActionDispatch::IntegrationTest
    def setup
      super
      @badbigbbox = %w[-0.1,-0.1,1.1,1.1 10,10,11,11]
      @badmalformedbbox = %w[-0.1 hello
                             10N2W10.1N2.1W]
      @badlatmixedbbox = %w[0,0.1,0.1,0 -0.1,80,0.1,70 0.24,54.34,0.25,54.33]
      @badlonmixedbbox = %w[80,-0.1,70,0.1 54.34,0.24,54.33,0.25]
      # @badlatlonoutboundsbbox = %w{ 191,-0.1,193,0.1  -190.1,89.9,-190,90 }
      @goodbbox = %w[-0.1,-0.1,0.1,0.1 51.1,-0.1,51.2,0
                     -0.1,%20-0.1,%200.1,%200.1 -0.1edcd,-0.1d,0.1,0.1 -0.1E,-0.1E,0.1S,0.1N S0.1,W0.1,N0.1,E0.1]
      # That last item in the goodbbox really shouldn't be there, as the API should
      # really reject it, however this is to test to see if the api changes.
    end

    ##
    # test all routes which lead to this controller
    def test_routes
      assert_routing(
        { :path => "/api/0.6/trackpoints", :method => :get },
        { :controller => "api/tracepoints", :action => "index" }
      )
    end

    # Only trackable and identifiable traces are served, the points of
    # public and private traces are not in the response.
    def test_tracepoints_public_and_private
      %w[public private].each do |visibility|
        create(:trace, :without_validations, :visibility => visibility, :latitude => 1, :longitude => 1) do |trace|
          create(:tracepoint, :trace => trace, :latitude => 1 * GeoRecord::SCALE, :longitude => 1 * GeoRecord::SCALE)
          convert(trace)
        end
      end
      get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001")
      assert_response :success
      assert_select "gpx[version='1.0'][creator='OpenStreetMap.org']", :count => 1 do
        assert_select "trk", :count => 0
      end
    end

    def test_tracepoints_trackable
      point = create(:trace, :visibility => "trackable", :latitude => 51.51, :longitude => -0.14) do |trace|
        create(:tracepoint, :trace => trace, :trackid => 1, :latitude => (51.510 * GeoRecord::SCALE).to_i, :longitude => (-0.140 * GeoRecord::SCALE).to_i)
        create(:tracepoint, :trace => trace, :trackid => 2, :latitude => (51.511 * GeoRecord::SCALE).to_i, :longitude => (-0.141 * GeoRecord::SCALE).to_i)
        convert(trace)
      end
      minlon = point.longitude - 0.002
      minlat = point.latitude - 0.002
      maxlon = point.longitude + 0.002
      maxlat = point.latitude + 0.002
      bbox = "#{minlon},#{minlat},#{maxlon},#{maxlat}"
      get api_tracepoints_path(:bbox => bbox)
      assert_response :success
      assert_select "gpx[version='1.0'][creator='OpenStreetMap.org']", :count => 1 do
        assert_select "trk", :count => 1 do
          assert_select "name", :count => 0
          assert_select "desc", :count => 0
          assert_select "url", :count => 0
          assert_select "trkseg", :count => 2 do |trksegs|
            trksegs.each do |trkseg|
              assert_select trkseg, "trkpt", :count => 1 do |trkpt|
                assert_select trkpt[0], "time", :count => 1
              end
            end
          end
        end
      end
    end

    def test_tracepoints_identifiable
      point = create(:trace, :visibility => "identifiable", :latitude => 51.512, :longitude => 0.142) do |trace|
        create(:tracepoint, :trace => trace, :latitude => (51.512 * GeoRecord::SCALE).to_i, :longitude => (0.142 * GeoRecord::SCALE).to_i)
        convert(trace)
      end
      minlon = point.longitude - 0.002
      minlat = point.latitude - 0.002
      maxlon = point.longitude + 0.002
      maxlat = point.latitude + 0.002
      bbox = "#{minlon},#{minlat},#{maxlon},#{maxlat}"
      get api_tracepoints_path(:bbox => bbox)
      assert_response :success
      assert_select "gpx[version='1.0'][creator='OpenStreetMap.org']", :count => 1 do
        assert_select "trk", :count => 1 do
          assert_select "name", :count => 1
          assert_select "desc", :count => 1
          assert_select "url", :count => 1
          assert_select "trkseg", :count => 1 do
            assert_select "trkpt", :count => 1 do
              assert_select "time", :count => 1
            end
          end
        end
      end
    end

    def test_tracepoints_disabled
      with_settings(:traces_disabled => true) do
        get api_tracepoints_path(:bbox => "-0.1,-0.1,0.1,0.1")
        assert_response :not_found
      end
    end

    def test_index_without_bbox
      get api_tracepoints_path
      assert_response :bad_request
      assert_equal "The parameter bbox is required", @response.body, "A bbox param was expected"
    end

    def test_traces_page_less_than_zero
      -10.upto(-1) do |i|
        get api_tracepoints_path(:page => i, :bbox => "-0.1,-0.1,0.1,0.1")
        assert_response :bad_request
        assert_equal "Page number must be greater than or equal to 0", @response.body, "The page number was #{i}"
      end
      0.upto(10) do |i|
        get api_tracepoints_path(:page => i, :bbox => "-0.1,-0.1,0.1,0.1")
        assert_response :success, "The page number was #{i} and should have been accepted"
      end
    end

    def test_bbox_too_big
      @badbigbbox.each do |bbox|
        get api_tracepoints_path(:bbox => bbox)
        assert_response :bad_request, "The bbox:#{bbox} was expected to be too big"
        assert_equal "The maximum bbox size is #{Settings.max_request_area}, and your request was too large. Either request a smaller area, or use planet.osm", @response.body, "bbox: #{bbox}"
      end
    end

    def test_bbox_malformed
      @badmalformedbbox.each do |bbox|
        get api_tracepoints_path(:bbox => bbox)
        assert_response :bad_request, "The bbox:#{bbox} was expected to be malformed"
        assert_equal "The parameter bbox must be of the form min_lon,min_lat,max_lon,max_lat", @response.body, "bbox: #{bbox}"
      end
    end

    def test_bbox_lon_mixedup
      @badlonmixedbbox.each do |bbox|
        get api_tracepoints_path(:bbox => bbox)
        assert_response :bad_request, "The bbox:#{bbox} was expected to have the longitude mixed up"
        assert_equal "The minimum longitude must be less than the maximum longitude, but it wasn't", @response.body, "bbox: #{bbox}"
      end
    end

    def test_bbox_lat_mixedup
      @badlatmixedbbox.each do |bbox|
        get api_tracepoints_path(:bbox => bbox)
        assert_response :bad_request, "The bbox:#{bbox} was expected to have the latitude mixed up"
        assert_equal "The minimum latitude must be less than the maximum latitude, but it wasn't", @response.body, "bbox: #{bbox}"
      end
    end

    # Ensure the lat/lon is formatted as a decimal e.g. not 4.0e-05
    def test_lat_lon_xml_format
      point = create(:tracepoint, :latitude => (0.00004 * GeoRecord::SCALE).to_i, :longitude => (0.00008 * GeoRecord::SCALE).to_i)
      convert(point.trace)

      get api_tracepoints_path(:bbox => "0,0,0.1,0.1")
      assert_match(/lat="0.0000400"/, response.body)
      assert_match(/lon="0.0000800"/, response.body)
    end

    def test_point_without_timestamp_has_no_time
      trace = create(:trace, :visibility => "trackable")
      create(:tracepoint, :trace => trace, :latitude => 1 * GeoRecord::SCALE, :longitude => 1 * GeoRecord::SCALE, :timestamp => Time.utc(2026, 1, 1))
      create(:tracepoint, :trace => trace, :latitude => (1.0001 * GeoRecord::SCALE).to_i, :longitude => 1 * GeoRecord::SCALE, :timestamp => Time.utc(2026, 1, 2))
      trace.points.where(:latitude => (1.0001 * GeoRecord::SCALE).to_i).update_all(:timestamp => nil) # rubocop:disable Rails/SkipsModelValidations
      convert(trace)

      get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001")
      assert_response :success
      assert_select "trkpt", :count => 2
      assert_select "trkpt time", :count => 1
    end

    # The first page comes without a cursor and has the next page in the Link
    # header. The last page has no Link header.
    def test_cursor_pagination
      traces = Array.new(2) { create_trace_with_points(3) }

      with_settings(:tracepoints_per_page => 4) do
        # the newest trace first, so the first page has the 3 points of the
        # second trace and 1 point of the first
        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001")
        assert_response :success
        assert_select "trkpt", :count => 4
        assert_select "trk", :count => 2
        assert_select "trk url", :count => 2
        assert_select "trk:first-child url", :text => trace_url(traces.last)

        next_page = next_link
        assert_match(/cursor=/, next_page)

        get next_page
        assert_response :success
        assert_select "trkpt", :count => 2
        assert_select "trk", :count => 1
        assert_select "trk url", :text => trace_url(traces.first)
        assert_nil next_link

        # the cursor is the last point of the page, so the pages do not
        # overlap and no point is missing
        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001")
        first_times = response.body.scan(%r{<time>(.*?)</time>})
        get next_page
        second_times = response.body.scan(%r{<time>(.*?)</time>})
        assert_equal 6, (first_times + second_times).uniq.size
      end
    end

    def test_cursor_pagination_with_an_exact_number_of_pages
      create_trace_with_points(4)

      with_settings(:tracepoints_per_page => 2) do
        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001")
        assert_select "trkpt", :count => 2
        assert_not_nil next_link

        get next_link
        assert_select "trkpt", :count => 2
        assert_nil next_link
      end
    end

    def test_cursor_invalid
      ["not-base64!", Base64.urlsafe_encode64("1|2|3"), Base64.urlsafe_encode64("a|b|c|d")].each do |cursor|
        get api_tracepoints_path(:bbox => "-0.1,-0.1,0.1,0.1", :cursor => cursor)
        assert_response :bad_request, "The cursor #{cursor} was expected to be invalid"
        assert_equal "The cursor parameter is invalid", @response.body
      end
    end

    # The old page parameter still works, without a Link header.
    def test_page_pagination
      create_trace_with_points(5)

      with_settings(:tracepoints_per_page => 2) do
        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001", :page => 0)
        assert_response :success
        assert_select "trkpt", :count => 2
        assert_nil next_link

        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001", :page => 2)
        assert_response :success
        assert_select "trkpt", :count => 1

        get api_tracepoints_path(:bbox => "0.999,0.999,1.001,1.001", :page => 3)
        assert_response :success
        assert_select "trkpt", :count => 0
      end
    end

    private

    ##
    # convert the points of a trace into gpx_tracks rows, which is what the api reads
    def convert(trace)
      TraceLinestringJob.perform_now(trace)
    end

    ##
    # create an identifiable trace with count points at 1,1, one step north of
    # each other, and convert it
    def create_trace_with_points(count)
      create(:trace, :visibility => "identifiable", :latitude => 1, :longitude => 1) do |trace|
        count.times do |index|
          create(:tracepoint, :trace => trace, :latitude => ((1 + (0.00001 * index)) * GeoRecord::SCALE).to_i, :longitude => 1 * GeoRecord::SCALE,
                              :timestamp => Time.utc(2026, 1, 1) + (trace.id * 1000) + index)
        end
        convert(trace)
      end
    end

    ##
    # the url of a trace as it appears in the gpx
    def trace_url(trace)
      url_for(:controller => "/traces", :action => "show", :display_name => trace.user.display_name, :id => trace.id, :only_path => true)
    end

    ##
    # the url of the next page from the Link header, nil when there is none
    def next_link
      link = response.headers["Link"]
      return nil if link.nil?

      link[/<(.*)>; rel="next"/, 1]
    end
  end
end
