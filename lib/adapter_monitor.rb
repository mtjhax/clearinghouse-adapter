require 'win32/daemon'
require 'rbconfig'
require 'logger'

include Win32

RUBY = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])

ADAPTER_DIRECTORY = File.expand_path(File.dirname(__FILE__))
SYNC_COMMAND = "rake adapter_sync"
ERROR_NOTIFIER = File.expand_path("adapter_monitor_notification.rb", File.dirname(__FILE__))
LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor.log'), File.dirname(__FILE__))
ERROR_LOG_FILE = File.expand_path(File.join('..', 'log', 'adapter_monitor_errors.log'), File.dirname(__FILE__))

# TODO capture absolutely ALL exceptions and handle them
# TODO output errors to the Windows event log and alert notifications

class Daemon
  def service_init
    devnull = File.open(File::NULL, 'w')
    $stdout.reopen(devnull, 'w')
    $stderr.reopen(devnull, 'w')
    @logger = Logger.new(LOG_FILE, 'weekly')
    @error_count = 0
  end

  def service_main
    begin
      while running?
        @logger.info "Starting sync worker..."
        # TODO handling of stdout and stderr is not optimal - they dump to an extra log file
        pid = spawn(SYNC_COMMAND, out:[ERROR_LOG_FILE, 'a'], err:[:child, :out], chdir: ADAPTER_DIRECTORY)

        # TODO rescue from SystemError if child never started
        pid, status = Process.wait2(pid)
        @logger.info "Worker process complete, pid #{pid} status #{status}"

        handle_worker_error(status) if status != 0

        sleep 5
      end
    rescue Exception => e
      @logger.error e.message + "\n" + e.backtrace.join("\n")
    end
  end

  def service_stop
    # TODO when service stopped, if we have an interest in a child process, register disinterest and exit(?)
    exit
  end

  def handle_worker_error(status)
    @error_count += 1
    if @error_count == 1
      @logger.info "Sending error notification"
      pid = spawn("\"#{RUBY}\" \"#{ERROR_NOTIFIER}\"", out:[ERROR_LOG_FILE, 'a'], err:[:child, :out])
      pid, status = Process.wait2(pid)
      if status != 0
        @logger.info "Error notification failed, check logs"
      else
        @logger.info "Error notification complete"
      end
    end
  end

end

Daemon.mainloop
