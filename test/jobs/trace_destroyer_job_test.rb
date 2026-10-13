# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class TraceDestroyerJobTest < ActiveJob::TestCase
  def test_destroy_contents_called
    trace = Minitest::Mock.new

    # Tiny little bit of mocking to make activejob happy
    trace.expect :is_a?, false, [TraceDestroyerJob]

    # Check that trace.destroy_contents is called
    trace.expect :destroy_contents, true

    TraceDestroyerJob.perform_now(trace)

    assert_mock trace
  end
end
