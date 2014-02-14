module Processor
  class Base
    def process_trip_hash( trip_hash )
      trip_hash # no-op
    end
  end
end

class PreProcessor < Processor::Base; end

class PostProcessor < Processor::Base; end
