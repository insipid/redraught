require_relative 'spec_helper'
require_relative '../app'

RSpec.describe 'Redraught routes' do
  def app = Sinatra::Application

  let(:tmpdir) { Dir.mktmpdir }
  let(:pipeline_yml) do
    path = File.join(tmpdir, 'test.yml')
    File.write(path, <<~YAML)
      name: Test
      description: Test pipeline
      output_extension: md
      steps:
        - id: clean
          name: Clean
          description: Clean text
          prompt: Clean this.
    YAML
    path
  end

  before do
    stub_const('DATA_DIR', tmpdir)
    stub_const('PIPELINES_DIR', tmpdir)
    FileUtils.mkdir_p(File.join(tmpdir, 'sessions'))
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe 'GET /' do
    it 'returns 200' do
      get '/'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'POST /sessions' do
    it 'creates a session and redirects to it' do
      tmpfile = Tempfile.new(['transcript', '.txt'])
      tmpfile.write('hello transcript')
      tmpfile.rewind

      post '/sessions', {
        name: 'test-session',
        pipeline: File.basename(pipeline_yml),
        transcript: Rack::Test::UploadedFile.new(tmpfile.path, 'text/plain')
      }
      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/sessions/')
    ensure
      tmpfile.close
      tmpfile.unlink
    end
  end

  describe 'GET /sessions/:id/steps/:n' do
    let(:session) { Session.create(tmpdir, 'test', pipeline_yml, 'transcript content') }

    it 'returns step data as JSON' do
      get "/sessions/#{session.id}/steps/1"
      expect(last_response.status).to eq(200)
      data = JSON.parse(last_response.body)
      expect(data['input']).to eq('transcript content')
      expect(data['status']).to eq('pending')
      expect(data['prompt']).to eq('Clean this.')
    end
  end

  describe 'PUT /sessions/:id/steps/:n' do
    let(:session) { Session.create(tmpdir, 'test', pipeline_yml, 'transcript content') }

    it 'saves content and returns success' do
      put "/sessions/#{session.id}/steps/1",
          { content: 'edited content' }.to_json,
          { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)['success']).to be true
      expect(session.step_content(1)).to eq('edited content')
    end
  end
end
