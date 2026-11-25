require 'yaml'

class Pipeline
  DEFAULT_COMMAND            = "llm -s {prompt} < {input}"
  DEFAULT_COMMAND_WITH_MODEL = "llm -m {model} -s {prompt} < {input}"

  attr_reader :name, :description, :output_extension, :command_template, :steps, :model

  def self.load(path)
    new(YAML.load_file(path))
  end

  def initialize(data)
    @name             = data['name']
    @description      = data['description']
    @output_extension = data['output_extension'] || 'md'
    @model            = data['model']
    default_cmd       = @model ? DEFAULT_COMMAND_WITH_MODEL : DEFAULT_COMMAND
    @command_template = data['command'] || default_cmd
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
      @model_override            = data['model']
      @pipeline                  = pipeline
    end

    def model
      @model_override || @pipeline.model
    end

    def output_extension
      @output_extension_override || @pipeline.output_extension
    end

    def command_template
      if @command_override
        @command_override
      elsif @model_override
        Pipeline::DEFAULT_COMMAND_WITH_MODEL
      else
        @pipeline.command_template
      end
    end

    def output_filename
      format('%02d-%s.%s', index, id, output_extension)
    end
  end
end
