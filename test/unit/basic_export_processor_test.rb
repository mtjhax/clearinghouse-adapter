require 'test_helper'
require 'support/file_helpers'
require 'hash'
require_relative '../../processors/basic_export_processor'

describe ExportProcessor do
  include FileHelpers

  before do
    @trip_result = {
      "actual_drop_off_time" => "2000-01-01T02:45:00Z",
      "actual_pick_up_time" => "2000-01-01T02:45:00Z",
      "base_fare" => "123.0",
      "billable_mileage" => 123.0,
      "created_at" => "2013-06-27T19:45:08-07:00",
      "driver_id" => "Fred",
      "extra_securement_count" => 123,
      "fare" => "123.0",
      "fare_type" => nil,
      "id" => 1,
      "miles_traveled" => 123.0,
      "odometer_end" => 123.0,
      "odometer_start" => 123.0,
      "outcome" => "Completed",
      "rate" => "123.0",
      "rate_type" => nil,
      "trip_claim_id" => nil,
      "trip_ticket_id" => 11,
      "updated_at" => "2013-06-27T19:45:08-07:00",
      "vehicle_id" => nil,
      "vehicle_type" => nil
    }
    @trip_ticket_comment = {
      "body" => "So cool!",
      "created_at" => "2013-04-02T13:06:09-07:00",
      "id" => 6,
      "trip_ticket_id" => 80,
      "updated_at" => "2013-06-27T17:32:16-07:00",
      "user_id" => 1
    }
    @trip_claim = {
      "claimant_customer_id" => nil,
      "claimant_provider_id" => 3,
      "claimant_service_id" => nil,
      "claimant_trip_id" => nil,
      "created_at" => "2013-06-26T11:22:57-07:00",
      "id" => 11,
      "notes" => nil,
      "proposed_fare" => nil,
      "proposed_pickup_time" => "2013-06-27T17:29:57-07:00",
      "status" => "pending",
      "trip_ticket_id" => 80,
      "updated_at" => "2013-06-27T17:32:59-07:00"
    }
    @big_ticket_hash = {
      "id" => 80,
      "rescinded" => false,
      "origin_provider_id" => 2,
      "origin_customer_id" => "4717",
      "origin_trip_id" => 1880,
      "pick_up_location_id" => nil,
      "drop_off_location_id" => nil,
      "customer_address_id" => 147,
      "customer_first_name" => "Walter",
      "customer_last_name" => "Vasquez",
      "customer_middle_name" => nil,
      "customer_dob" => "1994-07-04",
      "customer_primary_phone" => "825-520-4849",
      "customer_emergency_phone" => nil,
      "customer_primary_language" => nil,
      "customer_ethnicity" => nil,
      "customer_race" => nil,
      "customer_information_withheld" => true,
      "customer_identifiers" => {
        "a" => "b",
        "c" => "d"
      },
      "customer_notes" => nil,
      "customer_boarding_time" => 0,
      "customer_deboarding_time" => 0,
      "customer_seats_required" => 57,
      "customer_impairment_description" => nil,
      "customer_service_level" => nil,
      "customer_mobility_factors" => [
        "a_customer_mobility_factors",
        "b_customer_mobility_factors"
      ],
      "customer_service_animals" => nil,
      "customer_eligibility_factors" => nil,
      "num_attendants" => 0,
      "num_guests" => 0,
      "requested_pickup_time" => "2000-01-01T19:57:00Z",
      "earliest_pick_up_time" => nil,
      "appointment_time" => "2013-04-26T00:00:00-07:00",
      "requested_drop_off_time" => "2000-01-01T20:59:00Z",
      "allowed_time_variance" => -1,
      "trip_purpose_description" => nil,
      "trip_funders" => nil,
      "trip_notes" => nil,
      "scheduling_priority" => "dropoff",
      "created_at" => "2014-02-18 14:01:20.627780",
      "updated_at" => "2014-03-07 06:29:22.114344",
      "originator" => {
        "id" => 2,
        "name" => "Yahoo",
        "primary_contact_email" => "some@nights.fun",
        "address" => {
          "id" => 2,
          "address_1" => "123 Main St",
          "address_2" => nil,
          "city" => "Portland",
          "position" => nil,
          "state" => "OR",
          "zip" => "97210",
          "created_at" => "2013-03-21T08:03:22-07:00",
          "updated_at" => "2013-03-21T08:03:22-07:00"
        }
      },
      "customer_address" => {
        "id" => 147,
        "address_1" => "123 Main St",
        "address_2" => nil,
        "city" => "Portland",
        "position" => nil,
        "state" => "OR",
        "zip" => "97210",
        "created_at" => "2014-03-07T06:29:22-08:00",
        "updated_at" => "2014-03-07T06:29:22-08:00"
      },
      "pick_up_location" => nil,
      "drop_off_location" => nil,
      "trip_result" => @trip_result,
      "trip_claims" => [@trip_claim],
      "trip_ticket_comments" => [@trip_ticket_comment]
    }

    @export_folder = 'tmp/_export_test'
    FileUtils.mkpath @export_folder
    
    @options = { export_folder: @export_folder }
    @export_processor = ExportProcessor.new(nil, @options)
  end
  
  after do
    remove_test_folders(@export_folder)
  end
  
  describe "#process" do
    it "raises a runtime error if export directory is not configured" do
      @export_processor.options[:export_folder] = nil
      Proc.new { @export_processor.process([]) }.must_raise(RuntimeError)
    end
  
    it "raises a runtime error if export directory does not exist" do
      @export_processor.options[:export_folder] = 'tmp/__i/__dont/__exist'
      Proc.new { @export_processor.process([])}.must_raise(RuntimeError)
    end
    
    it "exports replicated changes as CSV files" do
      trip_changes = { 'update_type' => 'modified', 'id' => 1, 'customer_first_name' => 'Bob' }
      expected_headers = [ 'update_type', 'id', 'customer_first_name' ]
      @export_processor.expects(:export_csv).with(is_a(String), includes(*expected_headers), [trip_changes]).once
      @export_processor.stubs(:export_csv).with(is_a(String), [], [])
      @export_processor.process [ trip_changes ]
    end
    
    it "outputs new and modified trip tickets, claims, comments, and results to separate CSV files" do
      @export_processor.stubs(:timestamp_string).returns('timestamp')
      @export_processor.process([@big_ticket_hash])
      File.exist?(File.join(@export_folder, "trip_tickets.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_claims.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_ticket_comments.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_results.timestamp.csv")).must_equal true
    end
    
    describe "attribute values" do    
      before do
        @export_processor.stubs(:timestamp_string).returns('timestamp')
        @export_processor.process([@big_ticket_hash])

        csv_data = read_csv(@export_folder, "trip_tickets.timestamp.csv")
        csv_row = csv_data.first
        @flattened_hash = HashWithIndifferentAccess[csv_row.headers.zip(csv_row.fields)]
      end

      it "flattens location hashes by concatenating the keys together" do
        @flattened_hash.keys.must_include "customer_address_address_1"
        @flattened_hash["customer_address_address_1"].must_equal @big_ticket_hash["customer_address"]["address_1"]
      end

      it "flattens originator attributes and originator address attributes by concatenating the keys together" do
        @flattened_hash.keys.must_include "originator_name"
        @flattened_hash["originator_name"].must_equal @big_ticket_hash["originator"]["name"]

        @flattened_hash.keys.must_include "originator_address_address_1"
        @flattened_hash["originator_address_address_1"].must_equal @big_ticket_hash["originator"]["address"]["address_1"]
      end
  
      it "flattens array attributes into numbered columns" do
        @flattened_hash.keys.must_include "customer_mobility_factors_1"
        @flattened_hash["customer_mobility_factors_1"].must_equal @big_ticket_hash["customer_mobility_factors"][0]

        @flattened_hash.keys.must_include "customer_mobility_factors_2"
        @flattened_hash["customer_mobility_factors_2"].must_equal @big_ticket_hash["customer_mobility_factors"][1]
      end
  
      it "flattens hstore attributes into numbered key and value columns" do
        @flattened_hash.keys.must_include "customer_identifiers_1_key"
        @flattened_hash["customer_identifiers_1_key"].must_equal @big_ticket_hash["customer_identifiers"].keys[0]

        @flattened_hash.keys.must_include "customer_identifiers_1_value"
        @flattened_hash["customer_identifiers_1_value"].must_equal @big_ticket_hash["customer_identifiers"].values[0]

        @flattened_hash.keys.must_include "customer_identifiers_2_key"
        @flattened_hash["customer_identifiers_2_key"].must_equal @big_ticket_hash["customer_identifiers"].keys[1]

        @flattened_hash.keys.must_include "customer_identifiers_2_value"
        @flattened_hash["customer_identifiers_2_value"].must_equal @big_ticket_hash["customer_identifiers"].values[1]
      end
    end
  
    describe "attribute headers" do
      before do
        @second_big_ticket_hash = @big_ticket_hash.merge({
          "customer_identifiers" => {
            "a" => "b",
          },
          "customer_address" => nil,
          "customer_mobility_factors" => nil,
          "customer_service_animals" => [
            "a_customer_service_animals",
            "b_customer_service_animals"
          ]          
        })
        @export_processor.stubs(:timestamp_string).returns('timestamp')
        @export_processor.process([@big_ticket_hash, @second_big_ticket_hash])

        csv_data = read_csv(@export_folder, "trip_tickets.timestamp.csv")

        csv_row = csv_data[0]
        @headers = csv_row.headers
        @first_flattened_hash = HashWithIndifferentAccess[csv_row.headers.zip(csv_row.fields)]

        csv_row = csv_data[1]
        @second_flattened_hash = HashWithIndifferentAccess[csv_row.headers.zip(csv_row.fields)]
      end
      
      it "creates columns for the largest set of each array attribute, but only populates the cells that are valued for other rows" do
        @headers.must_include "customer_mobility_factors_1"
        @first_flattened_hash["customer_mobility_factors_1"].must_equal @big_ticket_hash["customer_mobility_factors"][0]
        @second_flattened_hash["customer_mobility_factors_1"].must_be :blank?

        @headers.must_include "customer_mobility_factors_2"
        @first_flattened_hash["customer_mobility_factors_2"].must_equal @big_ticket_hash["customer_mobility_factors"][1]
        @second_flattened_hash["customer_mobility_factors_2"].must_be :blank?

        @headers.must_include "customer_service_animals_1"
        @first_flattened_hash["customer_service_animals_1"].must_be :blank?
        @second_flattened_hash["customer_service_animals_1"].must_equal @second_big_ticket_hash["customer_service_animals"][0]

        @headers.must_include "customer_service_animals_2"
        @first_flattened_hash["customer_service_animals_2"].must_be :blank?
        @second_flattened_hash["customer_service_animals_2"].must_equal @second_big_ticket_hash["customer_service_animals"][1]
      end
      
      it "creates key and value columns for the largest set of each hash attribute, but only populates the cells that are valued for other rows" do
        @headers.must_include "customer_identifiers_1_key"
        @first_flattened_hash["customer_identifiers_1_key"].must_equal @big_ticket_hash["customer_identifiers"].keys[0]
        @second_flattened_hash["customer_identifiers_1_key"].must_equal @second_big_ticket_hash["customer_identifiers"].keys[0]

        @headers.must_include "customer_identifiers_1_value"
        @first_flattened_hash["customer_identifiers_1_value"].must_equal @big_ticket_hash["customer_identifiers"].values[0]
        @second_flattened_hash["customer_identifiers_1_value"].must_equal @second_big_ticket_hash["customer_identifiers"].values[0]

        @headers.must_include "customer_identifiers_2_key"
        @first_flattened_hash["customer_identifiers_2_key"].must_equal @big_ticket_hash["customer_identifiers"].keys[1]
        @second_flattened_hash["customer_identifiers_2_key"].must_be :blank?

        @headers.must_include "customer_identifiers_2_value"
        @first_flattened_hash["customer_identifiers_2_value"].must_equal @big_ticket_hash["customer_identifiers"].values[1]
        @second_flattened_hash["customer_identifiers_2_value"].must_be :blank?
      end
      
      it "creates columns for known hashes (locations, originator), but only populates the cells that are valued for other rows" do
        @headers.must_include "customer_address_address_1"
        @first_flattened_hash["customer_address_address_1"].must_equal @big_ticket_hash["customer_address"]["address_1"]
        @second_flattened_hash["customer_address_address_1"].must_be :blank?
      end
    end
  end
end