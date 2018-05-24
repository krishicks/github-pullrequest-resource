#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'date'
require_relative 'base'
require_relative '../repository'

module Commands
  class Check < Commands::Base
    def output
      prs = repo.pull_requests

      if prs.size > 1
        sorted = prs.sort_by(&:timestamp)

        if input.version[:timestamp]
          version_dt = DateTime.parse(input.version[:timestamp])
          return sorted.drop_while { |pr| pr.timestamp < version_dt }
        end

        return sorted
      end

      prs
    end

    private

    def repo
      @repo ||= Repository.new(name: input.source.repo)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  command = Commands::Check.new
  puts JSON.generate(command.output)
end
