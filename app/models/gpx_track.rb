# frozen_string_literal: true

# == Schema Information
#
# Table name: gpx_tracks
#
#  gpx_id  :bigint           not null, primary key
#  trackid :integer          not null, primary key
#  geom    :geometry         not null
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
  belongs_to :trace, :foreign_key => "gpx_id", :inverse_of => :gpx_tracks
end
