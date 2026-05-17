# Redraught Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local Sinatra web app for incrementally redrafting transcripts through configurable AI pipeline steps, with a live side-by-side diff view.

**Architecture:** Ruby/Sinatra backend serves a single-page session view; all state lives as plain files on disk in a configurable data directory. LLM processing is handled by shelling out to the `llm` CLI via `Open3.capture3`. Frontend uses vanilla JS with `jsdiff` + `diff2html` (CDN) for live diff rendering.

**Tech Stack:** Ruby, Sinatra, RSpec, rack-test, vanilla JS, jsdiff (CDN), diff2html (CDN)

---

## File Map

| File | Responsibility |
|------|----------------|
| `Gemfile` | Ruby dependencies |
| `config.ru` | Rack entry point |
| `app.rb` | All Sinatra routes |
| `lib/pipeline.rb` | YAML pipeline loading, step resolution |
| `lib/session.rb` | Session creation, file I/O |
| `lib/runner.rb` | LLM command building + execution |
| `pipelines/podcast-cleanup.yml` | Example pipeline template |
| `views/layout.erb` | HTML shell, CDN script tags |
| `views/index.erb` | Session list + new session form |
| `views/session.erb` | Session working view (bootstraps JS) |
| `public/app.js` | All frontend behaviour |
| `public/app.css` | Styles |
| `spec/spec_helper.rb` | RSpec + rack-test setup |
| `spec/pipeline_spec.rb` | Pipeline unit tests |
| `spec/session_spec.rb` | Session unit tests |
| `spec/runner_spec.rb` | Runner unit tests |
| `spec/app_spec.rb` | Route integration tests |

---

### Task 1: Project Setup

**Files:**
- Create: `Gemfile`
- Create: `config.ru`
- Create: `app.rb`
- Create: `spec/spec_helper.rb`
- Create: `.gitignore`

- [ ] **Step 1: Create Gemfile**

```ruby
source 'https://rubygems.org'

gem 'sinatra', '~> 3.0'
gem 'puma'
gem 'rackup'

group :development do
  gem 'sinatra-contrib', '~> 3.0'  # provides sinatra/reloader
end

group :development, :test do
  gem 'rspec'
  gem 'rack-test'
end
```

- [ ] **Step 2: Install gems**

Run: `bundle install`
Expected: `Gemfile.lock` created, no errors.

- [ ] **Step 3: Create config.ru**

```ruby
require_relative 'app'
run Sinatra::Application
```

- [ ] **Step 4: Create app.rb skeleton**

```ruby
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
```

- [ ] **Step 5: Create spec/spec_helper.rb**

```ruby
require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

RSpec.configure do |config|
  config.include Rack::Test::Methods
end
```

- [ ] **Step 6: Create .gitignore**

```
Gemfile.lock
.bundle/
```

- [ ] **Step 7: Create required directories**

Run: `mkdir -p lib pipelines views public spec`

- [ ] **Step 8: Verify server starts**

Run: `bundle exec rackup`
Expected: Server starts on port 9292. `curl http://localhost:9292/` returns `Redraught`. Stop the server (Ctrl+C).

- [ ] **Step 9: Commit**

```bash
git init
git add Gemfile config.ru app.rb spec/spec_helper.rb .gitignore
git commit -m "chore: project setup"
```

---

### Task 2: Pipeline Class

**Files:**
- Create: `lib/pipeline.rb`
- Create: `spec/pipeline_spec.rb`
- Create: `pipelines/podcast-cleanup.yml`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/pipeline_spec.rb
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
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `bundle exec rspec spec/pipeline_spec.rb`
Expected: Failures — `uninitialized constant Pipeline`.

- [ ] **Step 3: Implement Pipeline**

```ruby
# lib/pipeline.rb
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
      @index                   = index
      @id                      = data['id']
      @name                    = data['name']
      @description             = data['description']
      @prompt                  = data['prompt'].to_s.strip
      @output_extension_override = data['output_extension']
      @command_override        = data['command']
      @pipeline                = pipeline
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
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `bundle exec rspec spec/pipeline_spec.rb`
Expected: All examples pass.

- [ ] **Step 5: Create pipelines/podcast-cleanup.yml**

```yaml
name: Podcast Cleanup
description: Clean up a verbatim transcript into a readable article
output_extension: md

steps:
  - id: punctuation
    name: Add Punctuation
    description: Add punctuation, remove filler words and false starts
    prompt: |
      Add appropriate punctuation to this verbatim transcript. Remove filler
      words (um, uh, like) and false starts. Make minimal changes — do not
      rephrase or restructure anything.

  - id: paragraphs
    name: Form Paragraphs
    description: Group sentences into coherent paragraphs
    prompt: |
      Group the sentences into coherent paragraphs based on topic shifts.
      Do not change any wording.

  - id: structure
    name: Improve Structure
    description: Reorder and restructure for readability
    prompt: |
      Improve the structure for readability. You may reorder sections but
      keep all content present.
```

- [ ] **Step 6: Commit**

```bash
git add lib/pipeline.rb spec/pipeline_spec.rb pipelines/podcast-cleanup.yml
git commit -m "feat: pipeline YAML loading"
```

---

### Task 3: Session Class

**Files:**
- Create: `lib/session.rb`
- Create: `spec/session_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/session_spec.rb
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
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `bundle exec rspec spec/session_spec.rb`
Expected: Failures — `uninitialized constant Session`.

- [ ] **Step 3: Implement Session**

```ruby
# lib/session.rb
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
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `bundle exec rspec spec/session_spec.rb`
Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/session.rb spec/session_spec.rb
git commit -m "feat: session management"
```

---

### Task 4: Runner Class

**Files:**
- Create: `lib/runner.rb`
- Create: `spec/runner_spec.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# spec/runner_spec.rb
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
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `bundle exec rspec spec/runner_spec.rb`
Expected: Failures — `uninitialized constant Runner`.

- [ ] **Step 3: Implement Runner**

```ruby
# lib/runner.rb
require 'open3'

class Runner
  def self.run(step, input_path, output_path, command_override: nil)
    command = if command_override && !command_override.strip.empty?
      command_override
    else
      resolve_command(step.command_template, step.prompt, input_path)
    end
    execute(command, output_path)
  end

  def self.resolve_command(template, prompt, input_path)
    template
      .gsub('{prompt}',    shell_quote(prompt.to_s))
      .gsub('{input}',     shell_quote(input_path.to_s))
  end

  private

  def self.execute(command, output_path)
    stdout, stderr, status = Open3.capture3(command)
    File.write(output_path, stdout) if status.success?
    { success: status.success?, output: stdout, stderr: stderr, exit_code: status.exitstatus }
  end

  def self.shell_quote(str)
    "'" + str.gsub("'", "'\\''") + "'"
  end
end
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `bundle exec rspec spec/runner_spec.rb`
Expected: All examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/runner.rb spec/runner_spec.rb
git commit -m "feat: LLM runner with command templating"
```

---

### Task 5: Sinatra Routes

**Files:**
- Modify: `app.rb`
- Create: `spec/app_spec.rb`

- [ ] **Step 1: Write failing route tests**

```ruby
# spec/app_spec.rb
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
```

- [ ] **Step 2: Run tests to confirm failure**

Run: `bundle exec rspec spec/app_spec.rb`
Expected: Failures — routes not fully implemented.

- [ ] **Step 3: Replace app.rb with full route implementation**

```ruby
require 'sinatra'
require 'json'
require 'fileutils'
require_relative 'lib/pipeline'
require_relative 'lib/session'
require_relative 'lib/runner'

require 'sinatra/reloader' if development?

DATA_DIR     = ENV.fetch('REDRAUGHT_DATA', File.expand_path('~/.redraught'))
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
  session = Session.load(DATA_DIR, params[:id])
  n       = params[:n].to_i
  step    = session.pipeline.steps[n - 1]
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
  session  = Session.load(DATA_DIR, params[:id])
  n        = params[:n].to_i
  body_data = (json_body rescue {})
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
```

- [ ] **Step 4: Run tests to confirm pass**

Run: `bundle exec rspec spec/app_spec.rb`
Expected: All examples pass.

- [ ] **Step 5: Run full test suite**

Run: `bundle exec rspec`
Expected: All examples pass.

- [ ] **Step 6: Commit**

```bash
git add app.rb spec/app_spec.rb
git commit -m "feat: Sinatra routes"
```

---

### Task 6: Views — Layout and Index

**Files:**
- Create: `views/layout.erb`
- Create: `views/index.erb`

- [ ] **Step 1: Create views/layout.erb**

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Redraught</title>
  <link rel="stylesheet" href="/app.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/diff2html/bundles/css/diff2html.min.css">
</head>
<body>
  <%= yield %>
  <script src="https://cdn.jsdelivr.net/npm/diff/dist/diff.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/diff2html/bundles/js/diff2html.min.js"></script>
  <script src="/app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create views/index.erb**

```erb
<div class="page-index">
  <h1>Redraught</h1>

  <section class="new-session">
    <h2>New Session</h2>
    <form action="/sessions" method="post" enctype="multipart/form-data">
      <label>
        Session name (optional)
        <input type="text" name="name" placeholder="my-podcast-ep42">
      </label>
      <label>
        Pipeline
        <select name="pipeline">
          <% @pipelines.each do |p| %>
            <option value="<%= p[:basename] %>"><%= p[:pipeline].name %></option>
          <% end %>
        </select>
      </label>
      <label>
        Transcript file
        <input type="file" name="transcript" accept=".txt,.md">
      </label>
      <p class="or-label">or paste transcript:</p>
      <textarea name="transcript_text" rows="6" placeholder="Paste transcript here…"></textarea>
      <button type="submit">Create Session</button>
    </form>
  </section>

  <% if @sessions.any? %>
    <section class="session-list">
      <h2>Sessions</h2>
      <ul>
        <% @sessions.each do |s| %>
          <li>
            <a href="/sessions/<%= s.id %>"><%= s.id %></a>
            &mdash; <%= s.pipeline.name %>
          </li>
        <% end %>
      </ul>
    </section>
  <% end %>
</div>
```

- [ ] **Step 3: Verify index renders**

Run: `bundle exec rackup`
Visit `http://localhost:9292/` — page loads with the new session form and no errors.

- [ ] **Step 4: Commit**

```bash
git add views/layout.erb views/index.erb
git commit -m "feat: index view"
```

---

### Task 7: Session View

**Files:**
- Create: `views/session.erb`

- [ ] **Step 1: Create views/session.erb**

```erb
<div id="app"
     data-session-id="<%= @session.id %>"
     data-step-count="<%= @session.pipeline.steps.length %>">

  <header id="topbar">
    <div class="topbar-left">
      <a href="/" class="home-link">Redraught</a>
      <span class="session-name"><%= @session.name %></span>
      <span class="pipeline-name"><%= @session.pipeline.name %></span>
    </div>
    <div class="topbar-right">
      <span id="step-indicator"></span>
      <button id="run-all-btn">Run All</button>
    </div>
  </header>

  <div id="layout">
    <nav id="sidebar">
      <% @session.pipeline.steps.each_with_index do |step, i| %>
        <div class="step-item" data-n="<%= i + 1 %>">
          <span class="step-number"><%= i + 1 %></span>
          <span class="step-name"><%= step.name %></span>
          <span class="step-badge status-<%= @session.step_status(i + 1) %>"
                data-status-n="<%= i + 1 %>">
            <%= @session.step_status(i + 1) %>
          </span>
        </div>
      <% end %>
    </nav>

    <main id="main-panel">
      <details id="prompt-strip">
        <summary>Prompt &amp; Command</summary>
        <div class="prompt-inner">
          <label>Prompt<textarea id="prompt-editor" rows="4"></textarea></label>
          <label>Command<input type="text" id="command-editor"></label>
          <div class="prompt-actions">
            <small>Edits are ephemeral (one run only) unless saved.</small>
          </div>
        </div>
      </details>

      <div id="panels">
        <div class="panel" id="input-panel">
          <h3>Input</h3>
          <pre id="input-content"></pre>
        </div>
        <div class="panel" id="output-panel">
          <div class="panel-header">
            <h3>Output</h3>
            <div class="panel-actions">
              <button id="run-step-btn">Run Step</button>
              <button id="save-output-btn">Save</button>
            </div>
          </div>
          <textarea id="output-editor"></textarea>
        </div>
      </div>

      <details id="diff-section" open>
        <summary>Diff</summary>
        <div id="diff-content"></div>
      </details>

      <div id="status-bar">
        <pre id="stderr-output"></pre>
      </div>
    </main>
  </div>
</div>
```

- [ ] **Step 2: Verify session view renders**

Create a session via the index page. Confirm the session page renders without server errors (JS panels will be empty until Task 8).

- [ ] **Step 3: Commit**

```bash
git add views/session.erb
git commit -m "feat: session view HTML"
```

---

### Task 8: Frontend JavaScript

**Files:**
- Create: `public/app.js`

- [ ] **Step 1: Create public/app.js**

```javascript
// public/app.js
(function () {
  const appEl = document.getElementById('app');
  if (!appEl) return;

  const sessionId = appEl.dataset.sessionId;
  const stepCount = parseInt(appEl.dataset.stepCount, 10);
  let currentStep = 1;

  const inputContent  = document.getElementById('input-content');
  const outputEditor  = document.getElementById('output-editor');
  const diffContent   = document.getElementById('diff-content');
  const promptEditor  = document.getElementById('prompt-editor');
  const commandEditor = document.getElementById('command-editor');
  const runStepBtn    = document.getElementById('run-step-btn');
  const runAllBtn     = document.getElementById('run-all-btn');
  const saveOutputBtn = document.getElementById('save-output-btn');
  const stepIndicator = document.getElementById('step-indicator');
  const stderrOutput  = document.getElementById('stderr-output');

  // --- Diff ---

  function updateDiff() {
    const left  = inputContent.textContent || '';
    const right = outputEditor.value || '';
    if (!left && !right) { diffContent.innerHTML = ''; return; }
    const patch = Diff.createPatch('document', left, right, '', '');
    diffContent.innerHTML = Diff2Html.html(patch, {
      drawFileList: false,
      matching: 'lines',
      outputFormat: 'line-by-line'
    });
  }

  outputEditor.addEventListener('input', updateDiff);

  // --- Load step ---

  async function loadStep(n) {
    currentStep = n;
    stepIndicator.textContent = `Step ${n} of ${stepCount}`;

    const resp = await fetch(`/sessions/${sessionId}/steps/${n}`);
    const data = await resp.json();

    inputContent.textContent = data.input  || '';
    outputEditor.value       = data.output || '';
    promptEditor.value       = data.prompt  || '';
    commandEditor.value      = data.command || '';
    stderrOutput.textContent = '';

    updateDiff();

    document.querySelectorAll('.step-item').forEach(el => {
      el.classList.toggle('active', parseInt(el.dataset.n, 10) === n);
    });
  }

  // --- Run step ---

  runStepBtn.addEventListener('click', async () => {
    runStepBtn.disabled    = true;
    runStepBtn.textContent = 'Running…';

    const resp = await fetch(`/sessions/${sessionId}/steps/${currentStep}/run`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ command: commandEditor.value })
    });
    const data = await resp.json();

    runStepBtn.disabled    = false;
    runStepBtn.textContent = 'Run Step';
    stderrOutput.textContent = data.stderr || '';

    if (data.success) {
      outputEditor.value = data.output || '';
      updateDiff();
      setBadge(currentStep, 'done');
    } else {
      stderrOutput.textContent = `Failed (exit ${data.exit_code})\n${data.stderr}`;
    }
  });

  // --- Save output ---

  saveOutputBtn.addEventListener('click', async () => {
    await fetch(`/sessions/${sessionId}/steps/${currentStep}`, {
      method:  'PUT',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ content: outputEditor.value })
    });
    setBadge(currentStep, 'done');
  });

  // --- Run all ---

  runAllBtn.addEventListener('click', async () => {
    runAllBtn.disabled    = true;
    runAllBtn.textContent = 'Running…';

    const resp    = await fetch(`/sessions/${sessionId}/run-all`, { method: 'POST' });
    const results = await resp.json();

    runAllBtn.disabled    = false;
    runAllBtn.textContent = 'Run All';

    results.forEach(r => setBadge(r.n, r.success ? 'done' : 'error'));
    if (results.length > 0) loadStep(results[results.length - 1].n);
  });

  // --- Sidebar navigation ---

  document.querySelectorAll('.step-item').forEach(el => {
    el.addEventListener('click', () => loadStep(parseInt(el.dataset.n, 10)));
  });

  function setBadge(n, status) {
    const el = document.querySelector(`[data-status-n="${n}"]`);
    if (!el) return;
    el.textContent = status;
    el.className   = `step-badge status-${status}`;
  }

  loadStep(1);
})();
```

- [ ] **Step 2: Verify step loading**

Start the server, create a session, open the session page. The transcript should appear in the left Input panel. No console errors.

- [ ] **Step 3: Verify sidebar navigation**

Click each step. The active highlight moves, the step indicator updates, and the input panel updates.

- [ ] **Step 4: Verify run step (requires `llm` CLI installed)**

Click "Run Step" on step 1. If `llm` is installed: output appears in right panel, diff renders below, sidebar badge turns green. If not installed: error message in the status bar.

- [ ] **Step 5: Verify live diff**

Type in the right (output) panel. Confirm the diff panel updates in real time showing additions and deletions.

- [ ] **Step 6: Commit**

```bash
git add public/app.js
git commit -m "feat: frontend step navigation, run, diff"
```

---

### Task 9: CSS Styling

**Files:**
- Create: `public/app.css`

- [ ] **Step 1: Create public/app.css**

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 14px;
  background: #f5f5f5;
  color: #222;
}

/* Index */
.page-index { max-width: 640px; margin: 48px auto; padding: 0 16px; }
.page-index h1 { font-size: 2rem; margin-bottom: 24px; }
.page-index h2 { font-size: 1.1rem; margin: 24px 0 12px; }
.page-index label { display: block; margin-bottom: 12px; font-weight: 500; }
.page-index input[type=text],
.page-index select,
.page-index textarea { display: block; width: 100%; margin-top: 4px; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font: inherit; }
.page-index .or-label { margin: 8px 0 4px; color: #6b7280; font-size: 0.85rem; }
.page-index button[type=submit] { margin-top: 12px; padding: 8px 16px; background: #2563eb; color: #fff; border: none; border-radius: 4px; cursor: pointer; font: inherit; }
.session-list ul { list-style: none; }
.session-list li { padding: 6px 0; border-bottom: 1px solid #e5e5e5; }
.session-list a { color: #2563eb; text-decoration: none; }

/* Top bar */
#topbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 16px;
  background: #1e293b;
  color: #f8fafc;
  position: sticky;
  top: 0;
  z-index: 10;
  height: 42px;
}
.topbar-left { display: flex; align-items: center; gap: 12px; }
.home-link { color: #94a3b8; text-decoration: none; font-weight: 600; }
.session-name { font-weight: 600; }
.pipeline-name { color: #94a3b8; font-size: 0.85rem; }
.topbar-right { display: flex; align-items: center; gap: 12px; }
#step-indicator { color: #94a3b8; font-size: 0.85rem; }

/* Layout */
#layout {
  display: grid;
  grid-template-columns: 200px 1fr;
  height: calc(100vh - 42px);
  overflow: hidden;
}

/* Sidebar */
#sidebar { background: #fff; border-right: 1px solid #e5e5e5; overflow-y: auto; padding: 8px 0; }
.step-item { display: flex; align-items: center; gap: 8px; padding: 8px 12px; cursor: pointer; border-left: 3px solid transparent; }
.step-item:hover { background: #f8fafc; }
.step-item.active { background: #eff6ff; border-left-color: #2563eb; }
.step-number { color: #94a3b8; font-size: 0.8rem; min-width: 16px; }
.step-name { flex: 1; font-size: 0.85rem; }
.step-badge { font-size: 0.7rem; padding: 2px 6px; border-radius: 10px; background: #e5e7eb; color: #6b7280; }
.step-badge.status-done { background: #dcfce7; color: #15803d; }
.step-badge.status-error { background: #fee2e2; color: #dc2626; }

/* Main panel */
#main-panel { display: flex; flex-direction: column; overflow: hidden; background: #fff; }

/* Prompt strip */
#prompt-strip { border-bottom: 1px solid #e5e5e5; background: #f8fafc; }
#prompt-strip > summary { padding: 8px 16px; cursor: pointer; font-size: 0.85rem; color: #475569; }
.prompt-inner { padding: 8px 16px 12px; display: flex; flex-direction: column; gap: 8px; }
.prompt-inner label { font-size: 0.8rem; font-weight: 500; color: #475569; display: flex; flex-direction: column; gap: 4px; }
#prompt-editor { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font: inherit; resize: vertical; }
#command-editor { width: 100%; padding: 6px 8px; border: 1px solid #ccc; border-radius: 4px; font: 0.8rem monospace; }
.prompt-actions { display: flex; justify-content: flex-end; }
.prompt-actions small { color: #94a3b8; }

/* Split panels */
#panels { display: grid; grid-template-columns: 1fr 1fr; flex: 1; overflow: hidden; border-bottom: 1px solid #e5e5e5; min-height: 0; }
.panel { display: flex; flex-direction: column; overflow: hidden; }
.panel + .panel { border-left: 1px solid #e5e5e5; }
.panel > h3 { padding: 6px 12px; font-size: 0.75rem; text-transform: uppercase; color: #94a3b8; border-bottom: 1px solid #e5e5e5; }
.panel-header { display: flex; justify-content: space-between; align-items: center; padding: 4px 12px; border-bottom: 1px solid #e5e5e5; }
.panel-header h3 { font-size: 0.75rem; text-transform: uppercase; color: #94a3b8; }
.panel-actions { display: flex; gap: 6px; }
#input-content { flex: 1; overflow: auto; padding: 12px; font-size: 0.85rem; white-space: pre-wrap; background: #fafafa; line-height: 1.5; }
#output-editor { flex: 1; border: none; outline: none; padding: 12px; font: 0.85rem/1.5 inherit; resize: none; }

/* Diff section */
#diff-section { border-bottom: 1px solid #e5e5e5; }
#diff-section > summary { padding: 6px 16px; cursor: pointer; font-size: 0.85rem; color: #475569; background: #f8fafc; }
#diff-content { max-height: 220px; overflow: auto; font-size: 0.8rem; }
.d2h-wrapper { margin: 0; }

/* Status bar */
#status-bar { padding: 6px 12px; background: #fafafa; }
#stderr-output { font-size: 0.75rem; color: #dc2626; white-space: pre-wrap; max-height: 60px; overflow: auto; }

/* Buttons */
button { padding: 4px 10px; border: 1px solid #d1d5db; border-radius: 4px; background: #fff; cursor: pointer; font: inherit; font-size: 0.8rem; }
button:hover { background: #f3f4f6; }
button:disabled { opacity: 0.5; cursor: not-allowed; }
#run-step-btn { background: #2563eb; color: #fff; border-color: #2563eb; }
#run-step-btn:hover:not(:disabled) { background: #1d4ed8; }
#run-all-btn { background: #059669; color: #fff; border-color: #059669; }
#run-all-btn:hover:not(:disabled) { background: #047857; }
#save-output-btn { background: #fff; }
```

- [ ] **Step 2: Verify layout**

Visit the index page and a session page. Confirm: sidebar on left, topbar fixed, split panels filling the remaining height, diff section below panels, status bar at bottom.

- [ ] **Step 3: Commit**

```bash
git add public/app.css
git commit -m "feat: CSS layout and styling"
```

---

### Task 10: End-to-End Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All examples pass, 0 failures.

- [ ] **Step 2: Create a session**

1. `bundle exec rackup`
2. Visit `http://localhost:9292/`
3. Leave name blank (should auto-generate), select "Podcast Cleanup", paste ~100 words of text
4. Confirm redirect to session page
5. Confirm transcript appears in the Input panel of Step 1

- [ ] **Step 3: Check step navigation**

Click each step in the sidebar. Confirm: active highlight moves, step indicator shows "Step N of 3", input panel updates.

- [ ] **Step 4: Expand prompt strip**

Click "Prompt & Command". Confirm the step's prompt text and the resolved `llm` command (with shell-quoted prompt) appear.

- [ ] **Step 5: Run a step**

Click "Run Step". Confirm the button shows "Running…" and is disabled. After completion: output fills the right panel, diff renders below, sidebar badge turns green.
(If `llm` is not installed: the status bar shows the error and the badge stays pending — that is correct behaviour.)

- [ ] **Step 6: Verify live diff**

Type in the right panel. Confirm the diff section updates in real time.

- [ ] **Step 7: Save and navigate**

Click "Save". Click step 2. Confirm step 2's Input panel shows the saved step-1 output.

- [ ] **Step 8: Test Run All**

Create a fresh session. Click "Run All". Confirm all pending steps run sequentially and the final step is active when complete.

- [ ] **Step 9: Inspect files on disk**

Run: `ls ~/.redraught/sessions/`
Confirm the session folder exists with `pipeline.yml`, `00-input.txt`, and numbered step output files.

- [ ] **Step 10: Final commit**

```bash
git add -A
git commit -m "chore: end-to-end verified, v0.1 complete"
```
