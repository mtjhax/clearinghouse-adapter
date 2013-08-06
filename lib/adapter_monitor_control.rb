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

require 'win32/service'
require 'rbconfig'

include Win32

RUBY = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
TARGET = File.expand_path("adapter_monitor.rb", File.dirname(__FILE__))

if ARGV[0] == "install"
  puts "Installing service..."

  Service.create(
    :service_name => 'ride_clearinghouse_adapter',
    :host => nil,
    :service_type => Service::WIN32_OWN_PROCESS,
    :description => 'Simplifies integration with the Ride Clearinghouse web service.',
    :start_type => Service::AUTO_START,
    :error_control => Service::ERROR_NORMAL,
    :binary_path_name => "\"#{RUBY}\" \"#{TARGET}\"",
    :service_start_name => 'LocalSystem',
    :display_name => 'Ride Clearinghouse Adapter'
  )
  puts "Done."
elsif ARGV[0] == "remove"
  puts "Removing service..."
  Service.delete('ride_clearinghouse_adapter')
  puts "Done."
else
  puts "Command not recognized, use install or remove."
end
