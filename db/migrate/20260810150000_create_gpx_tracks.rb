# frozen_string_literal: true

class CreateGpxTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :gpx_tracks, :primary_key => [:gpx_id, :trackid] do |t|
      t.bigint :gpx_id, :null => false
      t.integer :trackid, :null => false
      t.column :geom, "geometry(LineStringZM,4326)", :null => false
      t.index :geom, :using => :gist
      t.foreign_key :gpx_files, :column => :gpx_id
    end
  end
end
