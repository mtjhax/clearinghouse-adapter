module Processor
  module Export
    class Base
      attr_accessor :logger, :options, :errors
      
      def initialize(logger = nil, options = {})
        @logger = logger
        @options = options
        @errors = []
      end
  
      def process(data)
        raise "You must impliment this method in your ExportProcessor class"
      end
    end 
  end
end

# The default, no-op instance. Clients must provide their own export
# processor class
class ExportProcessor < Processor::Export::Base; end