require 'logger'

module Processor
  module Export
    class Base
      BASE_DIR = File.expand_path('..', File.dirname(__FILE__))

      attr_accessor :logger, :options, :errors
      
      def initialize(logger = nil, options = {})
        @logger = logger || Logger.new(STDOUT)
        @options = options
        @errors = []
      end
  
      def process(data)
        raise "You must impliment this method in your ExportProcessor class"
      end
      
      private
      
      # normalize accepted location coordinate formats to WKT
      # formats accepted:
      #   location_hash['lat'] and location_hash['lon']
      #   location_hash['position'] = "lon lat" (punctuation ignored except dash, e.g. lon:lat, lon,lat, etc.)
      #   location_hash['position'] = "POINT(lon lat)"
      def normalize_location_coordinates(location_hash)
        lat = location_hash.delete('lat')
        lon = location_hash.delete('lon')
        position = location_hash.delete('position')
        new_position = position
        if lon.present? && lat.present?
          new_position = "POINT(#{lon} #{lat})"
        elsif position.present?
          match = position.match(/^\s*([\d\.\-]+)[^\d-]+([\d\.\-]+)\s*$/)
          new_position = "POINT(#{match[1]} #{match[2]})" if match
        end
        location_hash['position'] = new_position if new_position
      end
    end
  end
end

# The default, no-op instance. Clients must provide their own export
# processor class
class ExportProcessor < Processor::Export::Base; end