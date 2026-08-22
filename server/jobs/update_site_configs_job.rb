# frozen_string_literal: true

require 'open3'
require 'que'
require_relative '../config'

# pulls the ftr-site-config clone the extractor reads.
#
# the configs are a git repo that gains sites & fixes to existing ones every
# few days, so a clone that's never pulled slowly goes stale and pages start
# coming out as readability's guess again. que-scheduler is what runs this
# daily: see server/que_schedule.yml.
class UpdateSiteConfigsJob < Que::Job
  # a pull that isn't done by now is stuck on the network rather than working
  PULL_TIMEOUT = 120

  # the schedule doesn't depend on this job succeeding, so a pull that fails is
  # better left in que_jobs with its error than retried fifteen times before the
  # next run comes round anyway
  self.maximum_retry_count = 0

  def run
    dir = Config.load.ftr_site_config_dir
    if dir.nil? || dir.strip.empty?
      puts 'no ftr_site_config_dir set, nothing to pull'
    elsif !File.directory?(dir)
      warn "ftr_site_config_dir #{dir} is not a directory, not pulling site configs"
    else
      puts "pulled site configs in #{dir}: #{self.class.git_pull(dir).strip}"
    end
  end

  # popen3 rather than capture3 because a pull that wedges has to be killable:
  # it would otherwise hold a que worker open for good. terminal prompts are off
  # so a clone that wants credentials fails instead of waiting for a tty
  def self.git_pull(dir)
    Open3.popen3({ 'GIT_TERMINAL_PROMPT' => '0' }, 'git', '-C', dir, 'pull', '--ff-only') do |stdin, stdout, stderr, wait_thr|
      stdin.close
      # whichever of these is still reading when we raise gets its stream shut
      # under it, and its complaint about that is noise on top of the real error
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }
      [out, err].each { |reader| reader.report_on_exception = false }

      unless wait_thr.join(PULL_TIMEOUT)
        Process.kill('KILL', wait_thr.pid)
        wait_thr.join
        raise "git pull in #{dir} timed out after #{PULL_TIMEOUT}s"
      end

      raise "git pull in #{dir} failed: #{err.value.strip}" unless wait_thr.value.success?

      out.value
    end
  rescue Errno::ENOENT
    raise "git is not installed, cannot update the site configs in #{dir}"
  end
end
