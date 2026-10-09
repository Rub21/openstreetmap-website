# frozen_string_literal: true

require "test_helper"

class GpxTrackTest < ActiveSupport::TestCase
  BBOX = BoundingBox.new(0.9, 0.9, 1.1, 1.1)

  def test_points_in_bbox_serves_trackable_and_identifiable_traces
    trackable = trace_with_points("trackable", 2)
    identifiable = trace_with_points("identifiable", 2)
    trace_with_points("public", 2)
    trace_with_points("private", 2)

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100)

    assert_equal [identifiable.id, identifiable.id, trackable.id, trackable.id], points.map(&:gpx_id)
    assert_equal [identifiable, trackable], points.map(&:trace).uniq
  end

  def test_points_in_bbox_leaves_out_the_points_outside_the_bbox
    # 4 points 0.04 degrees apart, the last one is outside the bbox but in the
    # same segment as the others
    trace_with_points("trackable", 4, :spacing => 0.04)

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100)

    assert_equal [1, 2, 3], points.map(&:path)
    assert_equal [0, 0, 0], points.map(&:segment)
  end

  def test_points_in_bbox_returns_the_points_in_page_order
    with_settings(:max_points_per_track_segment => 2) do
      older = trace_with_points("trackable", 3, :trackid => 2)
      trace_with_points("trackable", 3, :trackid => 1, :trace => older)
      newer = trace_with_points("trackable", 3)

      points = GpxTrack.points_in_bbox(BBOX, :limit => 100)

      assert_equal([[newer.id, 1, 0, 1], [newer.id, 1, 0, 2], [newer.id, 1, 1, 1],
                    [older.id, 1, 0, 1], [older.id, 1, 0, 2], [older.id, 1, 1, 1],
                    [older.id, 2, 0, 1], [older.id, 2, 0, 2], [older.id, 2, 1, 1]], points.map { |point| key(point) })
    end
  end

  def test_points_in_bbox_returns_the_point_data
    timestamp = Time.utc(2026, 1, 1, 12, 0, 0)
    trace = create(:trace)
    create(:tracepoint, :trace => trace, :latitude => 10_000_000, :longitude => 10_000_000, :altitude => 100.5, :timestamp => timestamp)
    create(:tracepoint, :trace => trace, :latitude => 10_000_100, :longitude => 10_000_200, :altitude => 101.5, :timestamp => timestamp + 1)
    TraceLinestringJob.perform_now(trace)

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100)

    assert_equal 2, points.size
    assert_equal [trace.id, 1, 0, 2], key(points.last)
    assert_in_delta 1.00001, points.last.latitude, 0.0000001
    assert_in_delta 1.00002, points.last.longitude, 0.0000001
    assert_in_delta 101.5, points.last.altitude, 0.001
    assert_equal timestamp + 1, points.last.timestamp
    assert_equal "1.0000100", points.last.lat.to_s
    assert_equal "1.0000200", points.last.lon.to_s
  end

  def test_points_in_bbox_keeps_the_points_without_timestamp
    trace = create(:trace)
    create(:tracepoint, :trace => trace, :latitude => 10_000_000, :longitude => 10_000_000, :timestamp => Time.utc(2026, 1, 1))
    create(:tracepoint, :trace => trace, :latitude => 10_000_100, :longitude => 10_000_000, :timestamp => Time.utc(2026, 1, 2))
    trace.points.where(:latitude => 10_000_100).update_all(:timestamp => nil) # rubocop:disable Rails/SkipsModelValidations
    TraceLinestringJob.perform_now(trace)

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100)

    assert_equal [Time.utc(2026, 1, 1), nil], points.map(&:timestamp)
  end

  def test_points_in_bbox_respects_the_limit
    trace_with_points("trackable", 5)

    assert_equal 3, GpxTrack.points_in_bbox(BBOX, :limit => 3).size
  end

  def test_cursor_continues_inside_a_segment
    trace_with_points("trackable", 5)
    all = GpxTrack.points_in_bbox(BBOX, :limit => 100)

    first = GpxTrack.points_in_bbox(BBOX, :limit => 2)
    second = GpxTrack.points_in_bbox(BBOX, :limit => 2, :after => key(first.last))
    third = GpxTrack.points_in_bbox(BBOX, :limit => 2, :after => key(second.last))
    fourth = GpxTrack.points_in_bbox(BBOX, :limit => 2, :after => key(third.last))

    assert_equal 5, all.size
    assert_equal(all.map { |point| key(point) }, (first + second + third).map { |point| key(point) })
    assert_equal 1, third.size
    assert_empty fourth
  end

  def test_cursor_continues_across_segments_and_traces
    with_settings(:max_points_per_track_segment => 2) do
      trace_with_points("trackable", 3)
      trace_with_points("trackable", 3)
      all = GpxTrack.points_in_bbox(BBOX, :limit => 100)

      first = GpxTrack.points_in_bbox(BBOX, :limit => 4)
      second = GpxTrack.points_in_bbox(BBOX, :limit => 4, :after => key(first.last))
      third = GpxTrack.points_in_bbox(BBOX, :limit => 4, :after => key(second.last))

      assert_equal 6, all.size
      assert_equal 4, first.size
      assert_equal 2, second.size
      assert_empty third
      assert_equal(all.map { |point| key(point) }, (first + second).map { |point| key(point) })
    end
  end

  def test_cursor_skips_the_segments_before_it
    older = trace_with_points("trackable", 2)
    newer = trace_with_points("trackable", 2)

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100, :after => [newer.id, 1, 0, 2])

    assert_equal([[older.id, 1, 0, 1], [older.id, 1, 0, 2]], points.map { |point| key(point) })
  end

  # The trace of the cursor was deleted between two pages, so its segments
  # are no longer there.
  def test_cursor_on_a_trace_that_was_deleted
    older = trace_with_points("trackable", 2)
    newer = trace_with_points("trackable", 2)
    newer.destroy

    points = GpxTrack.points_in_bbox(BBOX, :limit => 100, :after => [newer.id, 1, 0, 1])

    assert_equal([[older.id, 1, 0, 1], [older.id, 1, 0, 2]], points.map { |point| key(point) })
  end

  def test_offset_skips_points
    with_settings(:max_points_per_track_segment => 2) do
      trace_with_points("trackable", 5)
      all = GpxTrack.points_in_bbox(BBOX, :limit => 100)

      assert_equal(all.map { |point| key(point) }, GpxTrack.points_in_bbox(BBOX, :limit => 100, :offset => 0).map { |point| key(point) })
      assert_equal(all.drop(1).first(2).map { |point| key(point) }, GpxTrack.points_in_bbox(BBOX, :limit => 2, :offset => 1).map { |point| key(point) })
      assert_equal(all.drop(3).map { |point| key(point) }, GpxTrack.points_in_bbox(BBOX, :limit => 2, :offset => 3).map { |point| key(point) })
      assert_empty GpxTrack.points_in_bbox(BBOX, :limit => 2, :offset => 5)
      assert_empty GpxTrack.points_in_bbox(BBOX, :limit => 2, :offset => 50)
    end
  end

  def test_offset_counts_only_the_points_inside_the_bbox
    # One segment that goes out of the bbox and comes back: the third point
    # is outside, the steps are under 10 km so the segment is not split.
    trace = create(:trace)
    [1.0, 1.08, 1.14, 1.08, 1.0].each_with_index do |latitude, index|
      create(:tracepoint, :trace => trace, :latitude => (latitude * GeoRecord::SCALE).to_i, :longitude => GeoRecord::SCALE,
                          :timestamp => Time.utc(2026, 1, 1) + index)
    end
    TraceLinestringJob.perform_now(trace)

    assert_equal 1, trace.gpx_tracks.count
    assert_equal [1, 2, 4, 5], GpxTrack.points_in_bbox(BBOX, :limit => 100).map(&:path)
    assert_equal [2, 4, 5], GpxTrack.points_in_bbox(BBOX, :limit => 100, :offset => 1).map(&:path)
    assert_equal [4, 5], GpxTrack.points_in_bbox(BBOX, :limit => 100, :offset => 2).map(&:path)
    assert_equal [5], GpxTrack.points_in_bbox(BBOX, :limit => 100, :offset => 3).map(&:path)
  end

  private

  ##
  # create a trace with count points inside the bbox, one step north of each
  # other, in one track, and convert it into gpx_tracks rows
  # pass trace to add a track to an existing trace
  def trace_with_points(visibility, count, trackid: 1, spacing: 0.001, trace: nil)
    trace ||= create(:trace, :without_validations, :visibility => visibility)

    count.times do |index|
      create(:tracepoint, :trace => trace, :trackid => trackid,
                          :latitude => ((1 + (spacing * index)) * GeoRecord::SCALE).to_i,
                          :longitude => GeoRecord::SCALE,
                          :timestamp => Time.utc(2026, 1, 1) + (trackid * 1000) + index)
    end

    TraceLinestringJob.perform_now(trace)
    trace
  end

  ##
  # the cursor key of a point
  def key(point)
    [point.gpx_id, point.trackid, point.segment, point.path]
  end
end
