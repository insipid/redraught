require 'yaml'

class Pipeline
  DEFAULT_COMMAND = "llm -s {prompt} < {input}"

  attr_reader :name, :description, :output_extension, :command_template, :steps

  def self.load(path)
    new(YAML.load_file(path))
  end

  def initialize(data)
    @name             = data['name']
    @description      = data['description']
    @output_extension = data['output_extension'] || 'md'
    @command_template = data['command'] || DEFAULT_COMMAND
    @steps = (data['steps'] || []).each_with_index.map do |s, i|
      Step.new(s, i + 1, self)
    end
  end

  class Step
    attr_reader :index, :id, :name, :description, :prompt

    def initialize(data, index, pipeline)
      @index                     = index
      @id                        = data['id']
      @name                      = data['name']
      @description               = data['description']
      @prompt                    = data['prompt'].to_s.strip
      @output_extension_override = data['output_extension']
      @command_override          = data['command']
      @pipeline                  = pipeline
    end

    def output_extension
      @output_extension_override || @pipeline.output_extension
    end

    def command_template
      @command_override || @pipeline.command_template
    end

    def output_filename
      format('%02d-%s.%s', index, id, output_extension)
    end
  end
end
