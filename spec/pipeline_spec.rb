require 'fileutils'
require_relative '../lib/pipeline'

RSpec.describe Pipeline do
  let(:fixture_dir) { File.join(__dir__, 'fixtures') }
  let(:yaml_path)   { File.join(fixture_dir, 'test-pipeline.yml') }

  before do
    FileUtils.mkdir_p(fixture_dir)
    File.write(yaml_path, <<~YAML)
      name: Test Pipeline
      description: A test pipeline
      output_extension: md
      steps:
        - id: punctuation
          name: Add Punctuation
          description: Fix punctuation
          prompt: |
            Add punctuation.
        - id: paragraphs
          name: Form Paragraphs
          description: Group into paragraphs
          prompt: |
            Group into paragraphs.
          output_extension: txt
    YAML
  end

  after { FileUtils.rm_rf(fixture_dir) }

  describe '.load' do
    subject(:pipeline) { Pipeline.load(yaml_path) }

    it 'loads name and description' do
      expect(pipeline.name).to eq('Test Pipeline')
      expect(pipeline.description).to eq('A test pipeline')
    end

    it 'loads two steps' do
      expect(pipeline.steps.length).to eq(2)
    end

    it 'assigns step indices starting at 1' do
      expect(pipeline.steps[0].index).to eq(1)
      expect(pipeline.steps[1].index).to eq(2)
    end

    it 'uses pipeline output_extension for steps without override' do
      expect(pipeline.steps[0].output_extension).to eq('md')
    end

    it 'uses step-level output_extension when present' do
      expect(pipeline.steps[1].output_extension).to eq('txt')
    end

    it 'generates correct output filenames' do
      expect(pipeline.steps[0].output_filename).to eq('01-punctuation.md')
      expect(pipeline.steps[1].output_filename).to eq('02-paragraphs.txt')
    end

    it 'uses default command template when not specified' do
      expect(pipeline.steps[0].command_template).to eq(Pipeline::DEFAULT_COMMAND)
    end
  end
end
