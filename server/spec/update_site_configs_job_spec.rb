# frozen_string_literal: true

require 'open3'
require 'rspec'
require 'rspec/temp_dir'

ENV['RACK_ENV'] = 'test'

# server.rb is what points que & the config at the test database
require_relative '../server'
require_relative '../que_schedule'
require_relative '../jobs/update_site_configs_job'

RSpec.describe UpdateSiteConfigsJob do
  include_context 'uses temp dir'

  let(:origin) { File.join(temp_dir, 'origin') }
  let(:clone) { File.join(temp_dir, 'clone') }

  # a real clone rather than a stub: what the job is for is the pull working
  # against the layout ftr-site-config actually has
  def git(dir, *args)
    out, err, status = Open3.capture3({ 'GIT_TERMINAL_PROMPT' => '0' }, 'git', '-C', dir,
                                      '-c', 'user.email=tribune@example.com', '-c', 'user.name=tribune',
                                      '-c', 'commit.gpgsign=false',
                                      *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def config_dir(dir)
    allow(Config).to receive(:load).and_return(Config.new(ftr_site_config_dir: dir))
  end

  before do
    FileUtils.mkdir_p(origin)
    git(origin, 'init', '--initial-branch=main')
    File.write(File.join(origin, 'www.example.com.txt'), "body: //div[@id='story']\n")
    git(origin, 'add', '.')
    git(origin, 'commit', '-m', 'first config')
    Open3.capture3('git', 'clone', origin, clone)

    config_dir(clone)
  end

  it 'pulls the site configs the extractor reads' do
    File.write(File.join(origin, 'www.other.com.txt'), "body: //article\n")
    git(origin, 'add', '.')
    git(origin, 'commit', '-m', 'second config')

    described_class.run

    expect(File).to exist(File.join(clone, 'www.other.com.txt'))
  end

  # the pull is a network call against someone else's server, so it fails from
  # time to time. que records the error & the schedule brings it round again
  it 'fails the job when the pull fails' do
    FileUtils.rm_rf(File.join(origin, '.git'))

    expect { described_class.run }.to raise_error(/git pull in .* failed/)
  end

  it 'does nothing when no directory is configured' do
    config_dir('')

    expect { described_class.run }.to output(/nothing to pull/).to_stdout
  end

  it 'says so rather than pulling when the directory is not there' do
    config_dir(File.join(temp_dir, 'missing'))

    expect { described_class.run }.to output(/is not a directory/).to_stderr
  end

  # the schedule is a yml file that nothing parses until a worker is running, so
  # a typo in it would otherwise only show up in production
  describe 'the schedule that runs it' do
    it 'is valid & runs this job daily' do
      expect(Que::Scheduler.schedule.fetch('UpdateSiteConfigsJob').job_class).to eq(described_class)
    end
  end
end
