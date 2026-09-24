# frozen_string_literal: true

# == Schema Information
#
# Table name: gpx_tracks
#
#  gpx_id  :bigint           not null, primary key
#  trackid :integer          not null, primary key
#  segment :integer          not null, primary key
#  geom    :st_geometry      not null, geometry, 4326
#
# Indexes
#
#  index_gpx_tracks_on_geom  (geom) USING gist
#
# Foreign Keys
#
#  fk_rails_...  (gpx_id => gpx_files.id)
#

class GpxTrack < ApplicationRecord
  validates :trackid, :segment, :geom, :presence => true

  belongs_to :trace, :foreign_key => "gpx_id", :inverse_of => :gpx_tracks

  # One GPS point read out of a segment. path is its position in the segment,
  # starting at 1, so (gpx_id, trackid, segment, path) identifies a point.
  Point = Struct.new(:gpx_id, :trackid, :segment, :path, :latitude, :longitude, :altitude, :timestamp, :trace) do
    def lat
      GeoRecord::Coord.new(latitude)
    end

    def lon
      GeoRecord::Coord.new(longitude)
    end
  end

  # Segments read per query while filling a page, and segments counted per
  # query while skipping the points before the page in the old page mode.
  SEGMENT_BATCH = 20
  SKIP_BATCH = 200

  scope :bbox, ->(bbox) { where("gpx_tracks.geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)", bbox.min_lon, bbox.min_lat, bbox.max_lon, bbox.max_lat) }

  # Only points of these traces are served by the trackpoints API.
  SERVED_VISIBILITIES = %w[trackable identifiable].freeze

  # Returns one page of points inside the bbox, ordered by gpx_id desc,
  # trackid, segment and path. after is the last point of the previous page
  # as [gpx_id, trackid, segment, path]. offset is for the old page mode.
  #
  # First the keys of the segments in the bbox, then their points in batches
  # until the page is full, so only the segments of the page are opened.
  def self.points_in_bbox(bbox, limit:, offset: 0, after: nil)
    keys = segment_keys_in_bbox(bbox)

    # The traces are read by primary key; this is also where the visibility
    # filter lives, so the key query only has the bbox condition.
    traces = Trace.where(:id => keys.map(&:first).uniq, :visibility => SERVED_VISIBILITIES)
                  .includes(:user).index_by(&:id)
    keys = keys.select { |key| traces.key?(key.first) }

    # The keys are in page order, so the ones before the cursor come first. The
    # cursor segment stays, the page may continue inside it.
    keys = keys.drop_while { |key| before_cursor?(key, after) } if after

    points = []
    index, rows = offset.positive? ? skip_points(keys, bbox, offset) : [0, []]

    loop do
      rows.each { |row| points << Point.new(*row.first(7), Time.at(row.last).utc, traces[row.first]) }
      break if points.size >= limit || index >= keys.size

      rows = points_of_segments(keys[index, SEGMENT_BATCH], bbox, after)
      index += SEGMENT_BATCH
    end

    points.first(limit)
  end

  # Old page mode. Skips offset points by counting the points of each segment
  # in the bbox, without reading them, and opens only the segment where the
  # page starts. Returns the index of the next segment and the first rows.
  def self.skip_points(keys, bbox, offset)
    index = 0

    while index < keys.size
      counts = point_counts(keys[index, SKIP_BATCH], bbox)

      keys[index, SKIP_BATCH].each do |key|
        count = counts.fetch(key, 0)

        if offset < count
          rows = points_of_segments([key], bbox, nil).drop(offset)
          return [index + 1, rows]
        end

        offset -= count
        index += 1
      end
    end

    [index, []]
  end

  # Keys of the segments in the bbox, in page order. The bbox is the only
  # condition, so the GiST index is the only plan; visibility and cursor are
  # applied on the keys afterwards.
  def self.segment_keys_in_bbox(bbox)
    bbox(bbox).order(:gpx_id => :desc, :trackid => :asc, :segment => :asc)
              .pluck(:gpx_id, :trackid, :segment)
  end

  # True when the segment comes before the cursor in page order.
  def self.before_cursor?(key, after)
    gpx_id, trackid, segment = key
    cursor_gpx_id, cursor_trackid, cursor_segment, _path = after

    gpx_id > cursor_gpx_id ||
      (gpx_id == cursor_gpx_id && (trackid < cursor_trackid ||
                                   (trackid == cursor_trackid && segment < cursor_segment)))
  end

  # Points of these segments inside the bbox, in page order. A row is
  # gpx_id, trackid, segment, path, latitude, longitude, altitude, epoch.
  def self.points_of_segments(keys, bbox, after)
    points = where([:gpx_id, :trackid, :segment] => keys)
             .joins("CROSS JOIN LATERAL ST_DumpPoints(gpx_tracks.geom) AS point")
             .where("point.geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)", bbox.min_lon, bbox.min_lat, bbox.max_lon, bbox.max_lat)

    if after
      gpx_id, trackid, segment, path = after

      # Inside the cursor segment, only the points after the cursor.
      points = points.where(<<~SQL.squish, :gpx_id => gpx_id, :trackid => trackid, :segment => segment, :path => path)
        NOT (gpx_tracks.gpx_id = :gpx_id AND gpx_tracks.trackid = :trackid
             AND gpx_tracks.segment = :segment AND point.path[1] <= :path)
      SQL
    end

    points.order(:gpx_id => :desc, :trackid => :asc, :segment => :asc).order(Arel.sql("point.path[1]"))
          .pluck(:gpx_id, :trackid, :segment,
                 Arel.sql("point.path[1]"), Arel.sql("ST_Y(point.geom)"), Arel.sql("ST_X(point.geom)"),
                 Arel.sql("ST_Z(point.geom)"), Arel.sql("ST_M(point.geom)"))
  end

  # Number of points of these segments inside the bbox, by segment key.
  def self.point_counts(keys, bbox)
    where([:gpx_id, :trackid, :segment] => keys)
      .joins("CROSS JOIN LATERAL ST_DumpPoints(gpx_tracks.geom) AS point")
      .where("point.geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)", bbox.min_lon, bbox.min_lat, bbox.max_lon, bbox.max_lat)
      .group(:gpx_id, :trackid, :segment)
      .count
  end

  private_class_method :segment_keys_in_bbox, :before_cursor?, :points_of_segments, :skip_points, :point_counts
end
