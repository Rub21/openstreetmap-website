# frozen_string_literal: true

class TraceLinestringJob < ApplicationJob
  queue_as :traces

  # Converts trace points into one linestring per track, where Z is the
  # altitude and M is the timestamp in epoch seconds.
  # only trackable and identifiable traces are converted.
  def perform(trace = nil)
    if trace
      convert(trace)
    else
      Trace.visible.imported
           .where(:visibility => %w[trackable identifiable])
           .where.not(:id => GpxTrack.select(:gpx_id))
           .find_each { |eligible| convert(eligible) }
    end
  end

  private

  def convert(trace)
    sql = ApplicationRecord.sanitize_sql_array([<<~SQL.squish, trace.id])
      INSERT INTO gpx_tracks (gpx_id, trackid, geom)
      SELECT gpx_id, trackid,
             ST_SetSRID(
               ST_MakeLine(
                 ST_MakePoint(longitude / #{GeoRecord::SCALE}.0,
                              latitude / #{GeoRecord::SCALE}.0,
                              COALESCE(altitude, 0),
                              EXTRACT(EPOCH FROM "timestamp"))
                 ORDER BY "timestamp"
               ), 4326)
      FROM gps_points
      WHERE gpx_id = ?
      GROUP BY gpx_id, trackid
      ON CONFLICT (gpx_id, trackid) DO NOTHING
    SQL

    ApplicationRecord.connection.execute(sql)
  end
end
