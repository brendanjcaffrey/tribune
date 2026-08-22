# frozen_string_literal: true

# que-scheduler expects rails to have pulled activesupport in for it, and
# reaches for its core extensions (present?, index_by, time zones) as though
# they're ruby's own, so the whole of it has to be loaded here
require 'active_support/all'
require 'que/scheduler'

# que-scheduler is itself a que job: it wakes up, enqueues whatever the schedule
# below says is due, and re-enqueues itself. so the recurring jobs need nothing
# from the worker beyond this file being loaded & the migration having run.
Que::Scheduler.configure do |config|
  # the default location is relative to the working directory, which is only
  # ever the repo root by luck
  config.schedule_location = File.join(__dir__, 'que_schedule.yml')

  # outside rails there's no framework time zone to inherit, and the scheduler
  # refuses to guess. everything else here talks utc too
  config.time_zone = 'UTC'
end
