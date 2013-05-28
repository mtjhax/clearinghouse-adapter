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
        begin
          pid = spawn(SYNC_COMMAND, out:[ERROR_LOG_FILE, 'a'], err:[:child, :out], chdir: ADAPTER_DIRECTORY)
          pid, status = Process.wait2(pid)
          @logger.info "Worker process complete, pid #{pid} status #{status}"
          handle_worker_error("Adapter worker process exited with status #{status}") if status != 0
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
    # TODO when service stopped, if we have a child process running, register disinterest so exit is not delayed(?)
    exit
  end

  def handle_failure(error_msg)
    @logger.error error_msg
    @error_count += 1
    if @error_count == 1
      @logger.info "Sending failure notification"
      error_msg.gsub(/"/, '')
      pid = spawn("\"#{RUBY}\" \"#{ERROR_NOTIFIER}\" -e \"#{error_msg}\"", out:[ERROR_LOG_FILE, 'a'], err:[:child, :out])
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
