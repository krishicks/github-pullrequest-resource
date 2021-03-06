require_relative '../../assets/lib/commands/check'
require 'webmock/rspec'
require 'json'

describe Commands::Check do
  def check(payload)
    payload['source']['no_ssl_verify'] = true

    Input.instance(payload: payload)
    Commands::Check.new.output.map &:as_json
  end

  def stub_json(uri, body)
    stub_request(:get, uri)
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: body.to_json)
  end

  context 'when targetting a base branch other than master' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/statuses/abcdef', [])
      stub_json('https://api.github.com:443/repos/jtarchie/test/pulls?base=my-base-branch&per_page=100', [{ number: 1, head: { sha: 'abcdef', repo: { updated_at: '2011-01-27T19:14:43Z' } } }])
    end

    it 'retrieves pull requests for the specified base branch' do
      expect(check('source' => { 'repo' => 'jtarchie/test', 'base' => 'my-base-branch' })).to eq [{ 'ref' => 'abcdef', 'pr' => '1', 'updated_at' => '2011-01-27T19:14:43Z' }]
    end
  end

  context 'when there are no pull requests' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100', [])
    end

    it 'returns no versions' do
      expect(check('source' => { 'repo' => 'jtarchie/test' })).to eq []
    end

    context 'when there is a last known version' do
      it 'returns no versions' do
        payload = { 'version' => { 'ref' => '1' }, 'source' => { 'repo' => 'jtarchie/test' } }

        expect(check(payload)).to eq []
      end
    end
  end

  context 'when there is an open pull request' do
    before do
      stub_json('https://api.github.com:443/repos/jtarchie/test/pulls?per_page=100', [{ number: 1, head: { sha: 'abcdef', repo: { updated_at: '2011-01-27T19:14:43Z' } } }])
    end

    it 'returns a version for that pr' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [{ 'ref' => 'abcdef', 'pr' => '1', 'updated_at' => '2011-01-27T19:14:43Z' }]
    end

    context 'and the version is the same as the pull request' do
      it 'returns that pull request' do
        payload = { 'version' => { 'ref' => 'abcdef', 'pr' => '1' }, 'source' => { 'repo' => 'jtarchie/test' } }

        expect(check(payload)).to eq [
          { 'ref' => 'abcdef', 'pr' => '1', 'updated_at' => '2011-01-27T19:14:43Z' }
        ]
      end
    end

    context 'and the top commit has [ci skip] in its message' do
      before do
        stub_json('https://api.github.com:443/repos/jtarchie/test/pulls?per_page=100', [{ number: 1, head: { sha: 'abcdef' } }])
        stub_json('https://api.github.com:443/repos/jtarchie/test/commits/abcdef', sha: 'abcdef', commit: { message: 'foo [ci skip] bar' })
      end

      it 'returns no versions' do
        expect(check('source' => { 'repo' => 'jtarchie/test', 'ci_skip' => true }, 'version' => {})).to eq []
      end
    end
  end

  context 'when there is more than one open pull request' do
    before do
      stub_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100', [
                  { number: 1, head: { sha: 'abcdef', repo: { full_name: 'jtarchie/test', updated_at: '2011-01-27T19:14:43Z' } }, base: { repo: { full_name: 'jtarchie/test' } } },
                  { number: 2, head: { sha: 'zyxwvu', repo: { full_name: 'someotherowner/repo', updated_at: '2011-01-26T19:14:43Z' } }, base: { repo: { full_name: 'jtarchie/test' } } }
                ])
    end

    it 'returns all PRs ordered by when the pr repo was updated desc' do
      expect(check('source' => { 'repo' => 'jtarchie/test' }, 'version' => {})).to eq [
        { 'ref' => 'abcdef', 'pr' => '1', 'updated_at' => '2011-01-27T19:14:43Z' },
        { 'ref' => 'zyxwvu', 'pr' => '2', 'updated_at' => '2011-01-26T19:14:43Z' }
      ]
    end

    context 'and `disable_forks` is set to true' do
      it 'returns ' do
        expect(check('source' => { 'repo' => 'jtarchie/test', 'disable_forks' => true })).to eq [{ 'ref' => 'abcdef', 'pr' => '1', 'updated_at' => '2011-01-27T19:14:43Z' }]
      end
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
        { number: i, head: { sha: "abcdef-#{i}", repo: { full_name: 'jtarchie/test' } }, base: { repo: { full_name: 'jtarchie/test' } } }
      end

      stub_body_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100', pull_requests[0..49], 'Link' => '<https://api.github.com/repos/jtarchie/test/pulls?per_page=100&page=2>; rel="next"')
      stub_body_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&page=2', pull_requests[50..99])

      first_prs = check('source' => { 'repo' => 'jtarchie/test' })
      expect(first_prs.length).to eq 100
      Billy.proxy.reset

      stub_cache_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100')
      stub_cache_json('https://api.github.com/repos/jtarchie/test/pulls?per_page=100&page=2')
      second_prs = check('source' => { 'repo' => 'jtarchie/test' })

      expect(first_prs).to eq second_prs
      # expect A == B
    end
  end
end
