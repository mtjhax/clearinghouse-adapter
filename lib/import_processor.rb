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

require 'logger'

module Processor
  module Import
    class Base
      attr_accessor :logger, :options, :errors
      
      def initialize(logger = nil, options = {})
        @logger = logger || Logger.new('/dev/null')
        @options = options
        @errors = []
      end
  
      def process
        raise "You must impliment this method in your ImportProcessor class"
      end
      
      def finalize(imported_rows, skipped_rows, unposted_rows)
        raise "You must impliment this method in your ImportProcessor class"
      end
    end
  end
end

# The default, no-op instance. Clients must provide their own import
# processor class
class ImportProcessor < Processor::Import::Base; end