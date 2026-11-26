require 'tmpdir'
require 'fileutils'
require_relative '../lib/session'

RSpec.describe Session do
  let(:data_dir) { Dir.mktmpdir }
  let(:pipeline_path) do
    path = File.join(data_dir, 'test-pipeline.yml')
    File.write(path, <<~YAML)
      name: Test Pipeline
      description: Test
      output_extension: md
      steps:
        - id: punctuation
          name: Add Punctuation
          description: Fix punctuation
          prompt: Add punctuation.
    YAML
    path
  end

  after { FileUtils.rm_rf(data_dir) }

  describe '.create' do
    it 'creates a session directory' do
      session = Session.create(data_dir, 'my-test', pipeline_path, 'Hello world')
      expect(Dir.exist?(session.path)).to be true
    end

    it 'writes the transcript as 00-input.txt' do
      session = Session.create(data_dir, 'my-test', pipeline_path, 'Hello world')
      expect(File.read(File.join(session.path, '00-input.txt'))).to eq('Hello world')
    end

    it 'copies pipeline.yml into the session' do
      session = Session.create(data_dir, 'my-test', pipeline_path, 'Hello world')
      expect(File.exist?(File.join(session.path, 'pipeline.yml'))).to be true
    end

    it 'slugifies the session name' do
      session = Session.create(data_dir, 'My Test Session!', pipeline_path, 'x')
      expect(session.id).to match(/\d{4}-\d{2}-\d{2}-my-test-session/)
    end
  end

  describe '.list' do
    it 'returns sessions sorted newest first' do
      Session.create(data_dir, 'alpha', pipeline_path, 'x')
      sleep 0.01
      Session.create(data_dir, 'beta', pipeline_path, 'y')
      ids = Session.list(data_dir).map(&:id)
      expect(ids.first).to include('beta')
    end
  end

  describe '#step_content and #write_step' do
    let(:session) { Session.create(data_dir, 'test', pipeline_path, 'transcript text') }

    it 'returns transcript for step 0' do
      expect(session.step_content(0)).to eq('transcript text')
    end

    it 'returns nil for an unrun step' do
      expect(session.step_content(1)).to be_nil
    end

    it 'returns content after write_step' do
      session.write_step(1, 'processed text')
      expect(session.step_content(1)).to eq('processed text')
    end
  end

  describe '#step_status' do
    let(:session) { Session.create(data_dir, 'test', pipeline_path, 'transcript') }

    it 'returns pending for an unrun step' do
      expect(session.step_status(1)).to eq('pending')
    end

    it 'returns done after a step is written' do
      session.write_step(1, 'output')
      expect(session.step_status(1)).to eq('done')
    end
  end
end
