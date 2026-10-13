# frozen_string_literal: true

class TraceDestroyerJob < ApplicationJob
  queue_as :traces

  def perform(trace)
    trace.destroy_contents
  end
end
