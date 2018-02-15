require 'octokit'
require_relative '../pull_request'

module Filters
  class All
    def initialize(pull_requests: [], input: Input.instance)
      @input = input
    end

    def pull_requests
      @pull_requests ||= Octokit.pulls(input.source.repo, pull_options).sort_by { |pr1, pr2|
        pr1 <=> pr2
      }.map { |pr|
        PullRequest.new(pr: pr)
      }
    end

    private

    attr_reader :input

    def pull_options
      input.source.base ? { base: input.source.base } : {}
    end
  end
end
