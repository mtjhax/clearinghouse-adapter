require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

desc "Sync new trips and updates with the Clearinghouse"
task :adapter_sync do
  ruby "-Ilib -e \"require 'adapter_sync'; AdapterSync.new.poll\""
end

desc "Test if email notification is working"
task :notification_test do
  ruby "-Ilib -e \"require 'adapter_monitor_notification'; AdapterNotification.new(error: 'This is a test notification.').send\""
end


