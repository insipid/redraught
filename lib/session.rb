require 'fileutils'
require 'date'
require_relative 'pipeline'

class Session
  attr_reader :id, :path

  def self.create(data_dir, name, pipeline_path, transcript_content)
    date = Date.today.to_s
    slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
    id   = "#{date}-#{slug}"
    sessions_dir = File.join(data_dir, 'sessions')
    path = File.join(sessions_dir, id)

    if Dir.exist?(path)
      id   = "#{id}-#{Time.now.to_i}"
      path = File.join(sessions_dir, id)
    end

    FileUtils.mkdir_p(path)
    FileUtils.cp(pipeline_path, File.join(path, 'pipeline.yml'))
    File.write(File.join(path, '00-input.txt'), transcript_content)

    new(id, path)
  end

  def self.load(data_dir, id)
    path = File.join(data_dir, 'sessions', id)
    raise "Session not found: #{id}" unless Dir.exist?(path)
    new(id, path)
  end

  def self.list(data_dir)
    sessions_dir = File.join(data_dir, 'sessions')
    return [] unless Dir.exist?(sessions_dir)
    Dir.entries(sessions_dir)
       .reject { |e| e.start_with?('.') }
       .sort.reverse
       .map { |id| new(id, File.join(sessions_dir, id)) }
  end

  def initialize(id, path)
    @id   = id
    @path = path
  end

  def pipeline
    @pipeline ||= Pipeline.load(File.join(path, 'pipeline.yml'))
  end

  def name
    id.sub(/^\d{4}-\d{2}-\d{2}-/, '')
  end

  def step_file(n)
    return File.join(path, '00-input.txt') if n == 0
    File.join(path, pipeline.steps[n - 1].output_filename)
  end

  def step_content(n)
    f = step_file(n)
    File.exist?(f) ? File.read(f) : nil
  end

  def write_step(n, content)
    File.write(step_file(n), content)
  end

  def step_status(n)
    File.exist?(step_file(n)) ? 'done' : 'pending'
  end
end
