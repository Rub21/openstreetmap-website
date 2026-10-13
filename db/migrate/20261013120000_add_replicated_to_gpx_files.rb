# frozen_string_literal: true

class AddReplicatedToGpxFiles < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # A trace starts as replicated, meaning there is nothing to announce.
    # Existing traces are covered by the planet dump. A new trace is set to
    # false when its import finishes, and again when it changes later.
    add_column :gpx_files, :replicated, :boolean, :default => true, :null => false

    add_index :gpx_files, :id, :where => "NOT replicated", :name => "gpx_files_not_replicated_idx", :algorithm => :concurrently
  end
end
