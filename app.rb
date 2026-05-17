require 'sinatra'
require 'json'
require 'fileutils'
require_relative 'lib/pipeline'
require_relative 'lib/session'
require_relative 'lib/runner'

require 'sinatra/reloader' if development?

DATA_DIR      = ENV.fetch('REDRAUGHT_DATA', File.expand_path('~/.redraught'))
PIPELINES_DIR = File.join(__dir__, 'pipelines')

FileUtils.mkdir_p(File.join(DATA_DIR, 'sessions'))

helpers do
  def json_body
    request.body.rewind
    JSON.parse(request.body.read)
  end

  def pipeline_list
    Dir.glob(File.join(PIPELINES_DIR, '*.yml')).map do |path|
      { path: path, basename: File.basename(path), pipeline: Pipeline.load(path) }
    end
  end
end

get '/' do
  @sessions  = Session.list(DATA_DIR)
  @pipelines = pipeline_list
  erb :index
end

post '/sessions' do
  name = params[:name].to_s.strip
  name = Time.now.strftime('%H%M%S') if name.empty?
  pipeline_path = File.join(PIPELINES_DIR, params[:pipeline])
  transcript = if params[:transcript] && params[:transcript][:tempfile]
    params[:transcript][:tempfile].read
  else
    params[:transcript_text].to_s
  end

  session = Session.create(DATA_DIR, name, pipeline_path, transcript)
  redirect "/sessions/#{session.id}"
end

get '/sessions/:id' do
  @session = Session.load(DATA_DIR, params[:id])
  erb :session
end

get '/sessions/:id/steps/:n' do
  content_type :json
  session    = Session.load(DATA_DIR, params[:id])
  n          = params[:n].to_i
  step       = session.pipeline.steps[n - 1]
  input_path = session.step_file(n - 1)

  {
    n:           n,
    name:        step.name,
    description: step.description,
    input:       session.step_content(n - 1),
    output:      session.step_content(n),
    status:      session.step_status(n),
    prompt:      step.prompt,
    command:     Runner.resolve_command(step.command_template, step.prompt, input_path)
  }.to_json
end

post '/sessions/:id/steps/:n/run' do
  content_type :json
  session          = Session.load(DATA_DIR, params[:id])
  n                = params[:n].to_i
  body_data        = (json_body rescue {})
  command_override = body_data['command']

  step        = session.pipeline.steps[n - 1]
  input_path  = session.step_file(n - 1)
  output_path = session.step_file(n)

  Runner.run(step, input_path, output_path, command_override: command_override).to_json
end

put '/sessions/:id/steps/:n' do
  content_type :json
  session = Session.load(DATA_DIR, params[:id])
  n       = params[:n].to_i
  session.write_step(n, json_body['content'])
  { success: true }.to_json
end

post '/sessions/:id/run-all' do
  content_type :json
  session = Session.load(DATA_DIR, params[:id])
  results = []

  session.pipeline.steps.each_with_index do |step, i|
    n = i + 1
    next if session.step_status(n) == 'done'

    input_path  = session.step_file(n - 1)
    output_path = session.step_file(n)
    result      = Runner.run(step, input_path, output_path)
    results << { n: n }.merge(result)
    break unless result[:success]
  end

  results.to_json
end
