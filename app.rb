require 'sinatra'
require 'json'
require 'fileutils'
require_relative 'lib/pipeline'
require_relative 'lib/session'
require_relative 'lib/runner'

require 'sinatra/reloader' if development?

DATA_DIR = ENV.fetch('REDRAUGHT_DATA', File.expand_path('~/.redraught'))
PIPELINES_DIR = File.join(__dir__, 'pipelines')

FileUtils.mkdir_p(File.join(DATA_DIR, 'sessions'))

get '/' do
  'Redraught'
end
