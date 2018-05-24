# frozen_string_literal: true

require_relative '../../assets/lib/commands/check'
require 'webmock/rspec'
require 'json'

describe Commands::Check do
  def check(payload)
    payload['source']['skip_ssl_verification'] = true

    Input.instance(payload: payload)
    Commands::Check.new.output.map &:as_json
  end

  def stub_json(uri, body)
    stub_request(:get, uri)
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: body.to_json)
  end

  context 'when there are no pull requests' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [])
    end

    it 'returns no versions' do
      expect(check('source' => { 'repo' => 'jtarchie/test' })).to eq []
    end
  end

  context 'when there are open pull requests' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [
                  { number: 1, created_at: '2011-04-14T16:00:00Z', head: { sha: 'commit-A', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 2, created_at: '2011-04-14T16:10:00Z', head: { sha: 'commit-B', repo: { full_name: 'forked/repo' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 3, created_at: '2011-04-14T16:20:00Z', head: { sha: 'commit-C', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                ])

      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-A', {sha: "commit-A", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
      stub_json('https://api.github.com/repos/forked/repo/commits/commit-B', {sha: "commit-B", commit: { committer: { date: "2011-04-14T15:10:00Z" }}})
      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-C', {sha: "commit-C", commit: { committer: { date: "2011-04-14T16:00:49Z" }, message: 'foo [ci skip] bar' }})

      # this stub is only here because the ci skip code looks at the wrong repo
      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-B', {sha: "commit-B", commit: { committer: { date: "2011-04-14T15:10:00Z" }}})

    end

    it 'returns the prs' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [
        { 'ref' => 'commit-A', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' },
        { 'ref' => 'commit-B', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' },
        { 'ref' => 'commit-C', 'pr' => '3', 'timestamp' => '2011-04-14T16:20:00Z' }
      ]
    end

    it 'returns only non-fork PRs when disable_forks is set to true' do
      expect(check('source' => { 'repo' => 'jtarchie/test', 'disable_forks' => true  }, 'version' => {})).to eq [
        { 'ref' => 'commit-A', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' },
        # PR 2 is a fork
        { 'ref' => 'commit-C', 'pr' => '3', 'timestamp' => '2011-04-14T16:20:00Z' }
      ]
    end

    it 'does not return PRs with ci skip in the HEAD commit message when ci_skip is set to true' do
      expect(check('source' => { 'repo' => 'jtarchie/test', 'ci_skip' => true  }, 'version' => {})).to eq [
        { 'ref' => 'commit-A', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' },
        { 'ref' => 'commit-B', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
        # PR 3 is ci skipped
      ]
    end
  end

  context 'when there are open prs created in the same sequence as their commits were made' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [
                  { number: 1, created_at: '2011-04-14T16:00:00Z', head: { sha: 'commit-A', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 2, created_at: '2011-04-14T16:10:00Z', head: { sha: 'commit-B', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
                ])

      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-A', {sha: "commit-A", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-B', {sha: "commit-B", commit: { committer: { date: "2011-04-14T15:10:00Z" }}})
    end

    it 'returns the prs sorted by their created_at' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [
        { 'ref' => 'commit-A', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' },
        { 'ref' => 'commit-B', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when a known version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-B', 'timestamp' => '2011-04-14T16:10:00Z' })).to eq [
        { 'ref' => 'commit-B', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when an unknown version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-X', 'timestamp' => '2011-04-14T16:10:00Z' })).to eq [
        { 'ref' => 'commit-B', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end
  end

  context 'when there are open prs created in the reverse sequence that their commits were made' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [
                  { number: 1, created_at: '2011-04-14T16:00:00Z', head: { sha: 'commit-B', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 2, created_at: '2011-04-14T16:10:00Z', head: { sha: 'commit-A', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
                ])

      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-A', {sha: "commit-A", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-B', {sha: "commit-B", commit: { committer: { date: "2011-04-14T15:10:00Z" }}})
    end

    it 'returns the prs sorted by their created_at' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [
        { 'ref' => 'commit-B', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' },
        { 'ref' => 'commit-A', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when a known version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-B', 'timestamp' => '2011-04-14T16:10:00Z' })).to eq [
        { 'ref' => 'commit-A', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when an unknown version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-X', 'timestamp' => '2011-04-14T16:10:00Z' })).to eq [
        { 'ref' => 'commit-A', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end
  end

  context 'when an older pr is updated with a newer commit than the created_at of another pr' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [
                  { number: 1, created_at: '2011-04-14T16:00:00Z', head: { sha: 'commit-C', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 2, created_at: '2011-04-14T16:10:00Z', head: { sha: 'commit-A', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
                ])

      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-A', {sha: "commit-A", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
      # commit-B was replaced with commit-C
      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-C', {sha: "commit-C", commit: { committer: { date: "2011-04-14T16:20:00Z" }}})
    end

    it 'returns the prs sorted by the newer of their created_at and head commit date' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [
        { 'ref' => 'commit-A', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' },
        { 'ref' => 'commit-C', 'pr' => '1', 'timestamp' => '2011-04-14T16:20:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when a known version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-B', 'timestamp' => '2011-04-14T16:15:00Z' })).to eq [
        { 'ref' => 'commit-C', 'pr' => '1', 'timestamp' => '2011-04-14T16:20:00Z' }
      ]
    end

    it 'returns prs with a newer head commit date or created_at date when an unknown version with timestamp is provided' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'ref' => 'commit-X', 'timestamp' => '2011-04-14T16:15:00Z' })).to eq [
        { 'ref' => 'commit-C', 'pr' => '1', 'timestamp' => '2011-04-14T16:20:00Z' }
      ]
    end
  end

  context 'when a new pr is created for a commit made earlier than than the provided timestamp' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', [
                  { number: 2, created_at: '2011-04-14T16:10:00Z', head: { sha: 'commit-A', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
                ])

      stub_json('https://api.github.com/repos/jtarchie/test/commits/commit-A', {sha: "commit-A", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
    end

    it 'returns the pr' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => { 'timestamp' => '2011-04-14T15:10:00Z' })).to eq [
        { 'ref' => 'commit-A', 'pr' => '2', 'timestamp' => '2011-04-14T16:10:00Z' }
      ]
    end
  end

  context 'when targeting a base branch other than master' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/statuses/abcdef', [])
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?base=my-base-branch&per_page=100&state=open', [
        { number: 1, created_at: '2011-04-14T16:00:00Z', head: { sha: 'abcdef', repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } },
      ])
      stub_json('https://api.github.com/repos/jtarchie/test/commits/abcdef', {sha: "abcdef", commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
    end

    it 'retrieves pull requests for the specified base branch' do
      expect(check('source' => { 'repo' => 'jtarchie/test', 'base' => 'my-base-branch' })).to eq [{ 'ref' => 'abcdef', 'pr' => '1', 'timestamp' => '2011-04-14T16:00:00Z' }]
    end
  end

  context 'when paginating through many PRs' do
    def stub_body_json(uri, body, headers = {})
      stub_request(:get, uri)
        .to_return(headers: {
          'Content-Type' => 'application/json',
          'ETag' => Digest::MD5.hexdigest(body.to_json)
        }.merge(headers), body: body.to_json)
    end

    def stub_cache_json(uri)
      stub_request(:get, uri)
        .to_return(status: 304, body: '[]')
    end

    it 'uses the cache that already exists' do
      pull_requests = (1..100).map do |i|
        { number: i, created_at: '2011-04-14T16:00:00Z', head: { sha: "abcdef-#{i}", repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
      end

      pull_requests.each { |pr|
        stub_json("https://api.github.com/repos/jtarchie/test/commits/#{pr[:head][:sha]}", {sha: pr[:head][:sha], commit: { committer: { date: "2011-04-14T15:00:00Z" }}})
      }

      stub_body_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open', pull_requests[0..49], 'Link' => '<https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open&page=2>; rel="next"')
      stub_body_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open&page=2', pull_requests[50..99])

      first_prs = check('source' => { 'repo' => 'jtarchie/test' })
      expect(first_prs.length).to eq 100
      Billy.proxy.reset

      stub_cache_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open')
      stub_cache_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&state=open&page=2')
      second_prs = check('source' => { 'repo' => 'jtarchie/test' })

      expect(first_prs).to eq second_prs
      # expect A == B
    end
  end
end
