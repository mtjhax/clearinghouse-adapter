# Copyright 2013 Ride Connection
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'win32/daemon'
require 'rbconfig'
require 'logger'

include Win32

RUBY = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
RAKE = File.join(RbConfig::CONFIG['bindir'], 'rake')

ADAPTER_DIRECTORY = File.expand_path(File.join(File.dirname(__FILE__), '..'))
SYNC_COMMAND = %Q{"#{RUBY}" "#{RAKE}" adapter_sync}
ERROR_NOTIFIER = File.expand_path("adapter_monitor_notification.rb", File.dirname(__FILE__))
LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor.log'), File.dirname(__FILE__))
ERROR_LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor_errors.log'), File.dirname(__FILE__))

OUTAGE_THRESHOLD = 10              # number of consecutive failures that indicate a service outage
REPEAT_NOTIFICATION_LIMIT = 5      # minimum number of minutes between failures

class Daemon
  def service_init
    devnull = File.open(File::NULL, 'w')
    $stdout.reopen(devnull, 'w')
    $stderr.reopen(devnull, 'w')
    @logger = Logger.new(LOG_FILE, 'weekly')
    @errors_since_last_successful_poll = 0
    @errors_since_last_notification = 0
    @last_notification_time = nil
    @service_outage = false
  end

  def service_main
    begin
      while running?
        @logger.info "Starting sync worker with command [#{SYNC_COMMAND}] in directory [#{ADAPTER_DIRECTORY}]..."
        begin
          pid = spawn(SYNC_COMMAND, out:[ERROR_LOG_FILE, 'a'], err:[:child, :out], chdir: ADAPTER_DIRECTORY)
          pid, status = Process.wait2(pid)
          @logger.info "Worker process complete, pid #{pid} status #{status}"
          if status == 0
            @errors_since_last_successful_poll = 0
            @errors_since_last_notification = 0
            if @service_outage
              @service_outage = false
              send_service_restored_notification
            end
          else
            handle_failure("Adapter worker process exited with status #{status}")
          end
        rescue Exception => e
          handle_failure("Unhandled exception in AdapterMonitor: #{e.message + "\n" + e.backtrace.join("\n")}")
        end
        sleep 60
      end
    rescue Exception => e
      # extra rescue because this process is intended for continuous operation
      @logger.error e.message + "\n" + e.backtrace.join("\n")
    end
  end

  def service_stop
    exit
  end

  def handle_failure(error_msg)
    @errors_since_last_successful_poll += 1
    @errors_since_last_notification += 1
    @logger.error error_msg

    if !@service_outage && (notification_time_limit_achieved || service_outage)
      error_msg.gsub(/"/, '')
      error_msg << "\nErrors since last successful poll: #{@errors_since_last_successful_poll}"
      error_msg << "\nErrors since last notification: #{@errors_since_last_notification}"
      if service_outage
        @service_outage = true
        @logger.error "Service outage detected, no additional notifications will be sent"
        error_msg << "\nService outage detected, no additional notifications will be sent"
      end

      @logger.info "Sending failure notification"
      pid = spawn("\"#{RUBY}\" \"#{ERROR_NOTIFIER}\" -e \"#{error_msg}\"", out:[ERROR_LOG_FILE, 'a'], err:[:child, :out])
      pid, status = Process.wait2(pid)
      if status != 0
        @logger.error "Notification failed, check logs"
      else
        @logger.info "Notification complete"
        @errors_since_last_notification = 0
        @last_notification_time = Time.now
      end
    end
  end

  def send_service_restored_notification
    @logger.info "Sending service restored notification"
    msg = "Service outage has ended, polling restarted"
    pid = spawn("\"#{RUBY}\" \"#{ERROR_NOTIFIER}\" -e \"#{msg}\"", out:[ERROR_LOG_FILE, 'a'], err:[:child, :out])
    pid, status = Process.wait2(pid)
    if status != 0
      @logger.error "Notification failed, check logs"
    else
      @logger.info "Notification complete"
      @last_notification_time = nil
    end
  end

  def notification_time_limit_achieved
    @last_notification_time.nil? || Time.now - @last_notification_time > REPEAT_NOTIFICATION_LIMIT * 60
  end

  def service_outage
    @errors_since_last_successful_poll >= OUTAGE_THRESHOLD
  end
end

Daemon.mainloop
