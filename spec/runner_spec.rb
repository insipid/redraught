require 'tmpdir'
require 'fileutils'
require_relative '../lib/runner'

RSpec.describe Runner do
  describe '.resolve_command' do
    it 'substitutes {prompt} and {input}' do
      result = Runner.resolve_command("llm -s {prompt} < {input}", "add punctuation", "/path/to/in.txt")
      expect(result).to eq("llm -s 'add punctuation' < '/path/to/in.txt'")
    end

    it 'escapes single quotes in prompt' do
      result = Runner.resolve_command("llm -s {prompt} < {input}", "don't do this", "/in.txt")
      expect(result).to include("'don'\\''t do this'")
    end
  end

  describe '.run' do
    let(:tmpdir)      { Dir.mktmpdir }
    let(:input_path)  { File.join(tmpdir, 'input.txt') }
    let(:output_path) { File.join(tmpdir, 'output.txt') }

    before { File.write(input_path, 'hello world') }
    after  { FileUtils.rm_rf(tmpdir) }

    it 'writes stdout to output_path on success' do
      step = double('step', command_template: "cat {input}", prompt: "")
      Runner.run(step, input_path, output_path)
      expect(File.read(output_path)).to eq('hello world')
    end

    it 'returns success: true on exit 0' do
      step = double('step', command_template: "cat {input}", prompt: "")
      result = Runner.run(step, input_path, output_path)
      expect(result[:success]).to be true
    end

    it 'returns success: false on non-zero exit' do
      step = double('step', command_template: "false", prompt: "")
      result = Runner.run(step, input_path, output_path)
      expect(result[:success]).to be false
    end

    it 'uses command_override when provided, ignoring the step template' do
      step = double('step', command_template: "this-command-does-not-exist", prompt: "")
      result = Runner.run(step, input_path, output_path, command_override: "echo override")
      expect(result[:output]).to include('override')
    end
  end
end
