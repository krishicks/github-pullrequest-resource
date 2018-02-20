#!/usr/bin/env ruby

require 'json'
require_relative 'base'
require_relative '../repository'

module Commands
  class Check < Commands::Base
    def output
      prs = repo.pull_requests

      if prs.size > 1
        sha_dates = prs.inject({}) { |memo, pr|
          pr_commits = Octokit.pull_request_commits(input.source.repo, pr.id, { page: 1, per_page: 1 })
          commit = pr_commits[0]
          memo[commit.sha] = commit.commit.committer.date
          memo
        }
        return prs.sort { |l,r| sha_dates[l.sha] <=> sha_dates[r.sha] }
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
