require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb'].exclude(/processor_test/)
  t.verbose = true
end

namespace :test do
  Rake::TestTask.new('adapter') do |t|
    t.libs << "lib"
    t.libs << "test"
    t.test_files = FileList['test/**/*_test.rb'].exclude(/processor_test/)
    t.verbose = true
  end

  Rake::TestTask.new('basic_processors') do |t|
    t.libs << "lib"
    t.libs << "test"
    t.test_files = FileList['test/**/basic_*_processor_test.rb']
    t.verbose = true
  end

  Rake::TestTask.new('advanced_processors') do |t|
    t.libs << "lib"
    t.libs << "test"
    t.test_files = FileList['test/**/advanced_*_processor_test.rb']
    t.verbose = true
  end

  desc "Test if email notification is working"
  task :notification do
    ruby "-Ilib -e \"require 'adapter_monitor_notification'; AdapterNotification.new(error: 'This is a test notification.').send\""
  end
end

desc "Sync new trips and updates with the Clearinghouse"
task :adapter_sync do
  ruby "-Ilib -e \"require 'adapter_sync'; AdapterSync.new.poll\""
end
