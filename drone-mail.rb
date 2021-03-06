#!/usr/bin/env ruby
#

require 'aws-sdk-ses'

class Mail
  attr :client, :plugin, :drone

  def initialize
    aws_region = Plugin.new.aws_region || 'eu-west-1'
    @client = Aws::SES::Client.new(region: aws_region)
    @plugin = Plugin.new
    @drone = Drone.new
  end

  def encoding
    plugin.encoding || 'UTF-8'
  end

  def htmlbody
    <<~HEREDOC
    <h2>Drone <a href=#{drone.link}>Build #{drone.build}</a>: #{drone.status}</h2>

    <table>
    <tr><td>Branch</td><td align="left">#{drone.branch}</td></tr>
    <tr><td>Committer</td><td align="left">#{drone.author}</td></tr>
    <tr><td>Repository</td><td align="left">#{drone.repo_name}</td></tr>
    <tr><td>Commit</td><td align="left">#{drone.commit_link}</td></tr>
    <tr><td>Time taken</td><td align="left">#{time_taken}</td></tr>
    <table>
    HEREDOC
  end

  def textbody
    <<~HEREDOC
    Build #{drone.build} #{drone.status}: #{drone.link}

    Branch: #{drone.branch}
    Committer: #{drone.author}
    Repository: #{drone.repo_name}
    Commit: #{drone.commit_link}
    Time taken: #{time_taken}
    HEREDOC
  end

  def subject
    plugin.subject || "Drone build #{drone.build} #{drone.status}: #{drone.branch}"
  end

  def recipient
    return plugin.recipient if plugin.recipient
    drone.author_email
  end

  def payload
    {
      destination: {
        to_addresses: [
          recipient,
        ],
      },
      message: {
        body: {
          html: {
            charset: encoding,
            data: htmlbody,
          },
          text: {
            charset: encoding,
            data: textbody,
          },
        },
        subject: {
          charset: encoding,
          data: subject,
        },
      },
      source: plugin.sender,
    }
  end

  def status
    if drone.status == 'success'
      "succeeded"
    else
      "failed"
    end
  end

  def time_taken
    seconds = drone.finished.to_i - drone.started.to_i
    if seconds < 60
      return "#{seconds}s"
    end

    if seconds < 3600
      return Time.at(seconds).utc.strftime("%Mm %Ss")
    end

    Time.at(seconds).utc.strftime("%H:%M:%S")
  end

  def send_check
    return true if plugin.always_send

    if drone.status == 'success' && drone.prev_build_status == 'failure'
      true
    elsif drone.status == 'failure'
      true
    else
      false
    end
  end

  def send
    if send_check
      begin
        client.send_email(payload)
      rescue Aws::SES::Errors::ServiceError => error
        puts "Email not sent! Error message: #{error}"
      end
      puts "Build broken or recovered. Email sent to #{recipient}"
    else
      puts "Build in a good place. Not sending email."
    end
  end
end

class Drone
  # These are environment variables set by Drone itself
  def drone_env(name)
    ENV.fetch("DRONE_#{name.upcase}", nil)
  end

  def author
    drone_env("commit_author")
  end

  def author_email
    drone_env("commit_author_email")
  end

  def branch
    drone_env("commit_branch")
  end

  def build
    drone_env("build_number")
  end

  def status
    drone_env("job_status")
  end

  def started
    drone_env("build_started")
  end

  def finished
    drone_env("build_finished")
  end

  def link
    drone_env("build_link")
  end

  def repo_name
    drone_env("repo")
  end

  def repo_owner
    drone_env("repo_owner")
  end

  def sha
    drone_env("commit_sha")
  end

  def commit_message
    drone_env("commit_message")
  end

  def commit_link
    drone_env("commit_link")
  end

  def prev_build_status
    drone_env("prev_build_status")
  end
end

class Plugin
  # Any custom parameters
  def set_parameter(parameter_name, required = true)
    parameter = "PLUGIN_" + parameter_name.upcase

    if required && ENV[parameter].nil?
      abort("Must set #{parameter}")
    end

    return false if ENV[parameter].nil?

    ENV[parameter]
  end

  def sender
    set_parameter("sender")
  end

  # Set to send specifically to a recipient, if this is not set
  # then it will send automatically the email of the commit author
  def recipient
    set_parameter("recipient", false)
  end

  def always_send
    set_parameter("always_send", false)
  end

  def subject
    set_parameter("subject", false)
  end

  def aws_region
    set_parameter("aws_region", false)
  end

  def encoding
    set_parameter("encoding", false)
  end
end

Mail.new.send
