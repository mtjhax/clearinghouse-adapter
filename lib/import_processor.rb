module Processor
  module Import
    class Base
      attr_accessor :logger, :options, :errors
      
      def initialize(logger = nil, options = {})
        @logger = logger
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