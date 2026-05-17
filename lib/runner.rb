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
    quoted_prompt = shell_quote(prompt.to_s)
    quoted_input  = shell_quote(input_path.to_s)
    template
      .gsub('{prompt}') { quoted_prompt }
      .gsub('{input}')  { quoted_input }
  end

  private

  def self.execute(command, output_path)
    stdout, stderr, status = Open3.capture3(command)
    File.write(output_path, stdout) if status.success?
    { success: status.success?, output: stdout, stderr: stderr, exit_code: status.exitstatus }
  end

  def self.shell_quote(str)
    "'" + str.gsub("'") { "'\\''" } + "'"
  end
end
