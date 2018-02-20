#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../repository'

module Commands
  class Check < Commands::Base
    def output
      prs = repo.pull_requests

      if prs.size > 1
        sha_dates = prs.inject({}) { |memo, pr|
          commit = Octokit.commit(input.source.repo, pr.sha)
          memo[commit.sha] = commit.commit.committer.date
          memo
        }
        return prs.sort_by { |l,r| sha_dates[l.sha] }
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
