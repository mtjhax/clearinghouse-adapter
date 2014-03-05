module Processor
  class Base
    def process_trip_hash( trip_hash )
      trip_hash # no-op
    end
  end
end

class ExportProcessor < Processor::Base; end

class ImportProcessor < Processor::Base; end
