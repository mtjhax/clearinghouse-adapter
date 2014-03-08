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

require 'test_helper'
require 'fileutils'
require 'adapter_sync'
require 'support/import_helpers'

describe AdapterSync do
  include ImportHelpers

  before do
    @input_folder = 'tmp/_import_test'
    @output_folder = 'tmp/_import_test_out'
    @export_folder = 'tmp/_export_test'
    FileUtils.mkpath @input_folder
    FileUtils.mkpath @output_folder
    FileUtils.mkpath @export_folder
    @adapter_options = {
        import: { enabled: true, import_folder: @input_folder, completed_folder: @output_folder },
        export: { enabled: true, export_folder: @export_folder },
        processors: { pre_processor: '', post_processor: '' },
    }
    @adapter = AdapterSync.new(@adapter_options)
    DatabaseCleaner.clean_with(:truncation)
    AdapterNotification.any_instance.stubs(:send)
  end

  after do
    remove_test_folders(@input_folder, @output_folder, @export_folder)
  end

  describe AdapterSync, "#poll" do
    it "replicates changes from the Clearinghouse" do
      ApiClient.any_instance.expects(:get).with('trip_tickets/sync', has_key(:updated_since)).once.returns([])
      @adapter.replicate_clearinghouse
    end

    it "skips export step if not enabled" do
      @adapter.options[:export][:enabled] = false
      @adapter.expects(:export_csv).never
      @adapter.export_changes
    end

    it "exports replicated changes as CSV files" do
      trip_changes = { 'update_type' => 'modified', 'id' => 1, 'customer_first_name' => 'Bob' }
      expected_headers = [ 'update_type', 'id', 'customer_first_name' ]
      @adapter.trip_updates = [ trip_changes ]
      @adapter.expects(:export_csv).with(is_a(String), includes(*expected_headers), [trip_changes]).once
      @adapter.stubs(:export_csv).with(is_a(String), [], [])
      @adapter.export_changes
    end

    it "reports replication errors" do
      trip_mock = Minitest::Mock
      trip_mock.stubs(:data).returns({'this' => 'hash', 'lacks' => 'an id key'})
      @adapter.stubs(:get_updated_clearinghouse_trips).returns([ trip_mock ])
      AdapterNotification.any_instance.expects(:send).once
      @adapter.poll
    end

    it "skips import step if not enabled" do
      @adapter.options[:import][:enabled] = false
      Import.any_instance.expects(:from_folder).never
      @adapter.import_tickets
    end

    it "attempts to import flat files" do
      Import.any_instance.expects(:importable_files).with(@adapter_options[:import][:import_folder]).at_least_once.returns([])
      @adapter.import_tickets
    end
  end

  describe AdapterSync, "#replicate_clearinghouse" do
    before do
      VCR.insert_cassette "AdapterSync#replicate_clearinghouse test"
    end

    after do
      VCR.eject_cassette
    end

    it "requests trips updated since most recent tracked updated_at time" do
      @last_update_time = 5.days.from_now
      @trip_ticket = TripTicket.create(ch_updated_at: @last_update_time)
      ApiClient.any_instance.expects(:get).once.with('trip_tickets/sync', updated_since: @last_update_time.strftime('%Y-%m-%d %H:%M:%S.%6N'))
      @adapter.replicate_clearinghouse
    end

    it "requests all trips if there are no locally tracked trips" do
      ApiClient.any_instance.expects(:get).once.with('trip_tickets/sync', updated_since: nil)
      @adapter.replicate_clearinghouse
    end

    it "stores new and modified trips, claims, comments, and results in instance variables" do
      @adapter.replicate_clearinghouse
      @adapter.trip_updates.length.must_equal 7
      @adapter.claim_updates.length.must_equal 3
      @adapter.comment_updates.length.must_equal 7
      @adapter.result_updates.length.must_equal 1
    end
  end

  describe AdapterSync, "#export_changes" do
    before do
      VCR.insert_cassette "AdapterSync#replicate_clearinghouse test"
    end

    after do
      VCR.eject_cassette
    end

    it "raises a runtime error if export directory is not configured" do
      @adapter.options[:export][:export_folder] = nil
      Proc.new { @adapter.export_changes }.must_raise(RuntimeError)
    end

    it "raises a runtime error if export directory does not exist" do
      @adapter.options[:export][:export_folder] = 'tmp/__i/__dont/__exist'
      Proc.new { @adapter.export_changes }.must_raise(RuntimeError)
    end

    it "outputs new and modified trip tickets, claims, comments, and results to separate CSV files" do
      @adapter.replicate_clearinghouse
      @adapter.stubs(:timestamp_string).returns('timestamp')
      @adapter.export_changes
      File.exist?(File.join(@export_folder, "trip_tickets.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_claims.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_ticket_comments.timestamp.csv")).must_equal true
      File.exist?(File.join(@export_folder, "trip_results.timestamp.csv")).must_equal true
    end
  end

  describe AdapterSync, "#import_tickets" do
    before do
      @minimum_trip_attributes = {
        origin_trip_id: 111,
        origin_customer_id: 222,
        customer_first_name: 'Bob',
        customer_last_name: 'Smith',
        customer_dob: '1/2/1955',
        customer_primary_phone: '222-333-4444',
        customer_seats_required: 1,
        requested_pickup_time: '09:00',
        appointment_time: '3 August 2013, 10:00:00 UTC',
        requested_drop_off_time: '13:00',
        customer_information_withheld: false,
        scheduling_priority: 'pickup'
      }
      @customer_address_attributes = {
        customer_address_address_1: '5 Maple Brook Ln',
        customer_address_city: 'Arlington'
      }
      @posted_customer_address_attributes = {
        address_1: '5 Maple Brook Ln',
        city: 'Arlington'
      }
      @updated_trip_attributes = {
        origin_trip_id: 111,
        appointment_time: '3 August 2013, 10:00:00 UTC',
        customer_last_name: 'Nohara',
      }
    end

    it "raises a runtime error if import directory is not configured" do
      @adapter.options[:import][:import_folder] = nil
      Proc.new { @adapter.import_tickets }.must_raise(RuntimeError)
    end

    it "raises a runtime error if import directory does not exist" do
      @adapter.options[:import][:import_folder] = 'tmp/__i/__dont/__exist'
      Proc.new { @adapter.import_tickets }.must_raise(RuntimeError)
    end

    it "adds files that were imported previously to the skip_files argument" do
      file = create_csv(@input_folder, 'test1.csv', ['test','headers'], [['test','values']])
      FactoryGirl.create(:imported_file, file_name: file, modified: File.mtime(file), size: File.size(file), rows: 1)
      Import.any_instance.expects(:from_folder).with(@input_folder, @output_folder, [file]).once.returns([])
      @adapter.import_tickets
    end

    it "tracks imported files to prevent reimport" do
      file = create_csv(@input_folder, 'test2.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      file_size = File.size(file)
      file_time = File.mtime(file)
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_tickets
      ImportedFile.count.must_equal 1
      imported_file = ImportedFile.first
      imported_file.file_name.must_equal file
      imported_file.size.must_equal file_size
      imported_file.modified.must_equal file_time
      imported_file.rows.must_equal 1
    end


    it "supports import of nested objects" do
      attrs = @minimum_trip_attributes.merge(@customer_address_attributes)
      customer_address_attrs = { 'customer_address_attributes' => @posted_customer_address_attributes.stringify_keys }
      create_csv(@input_folder, 'test7.csv', attrs.keys, [attrs.values])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).with(:trip_tickets, has_entry(customer_address_attrs)).once.returns(stub_result)
      @adapter.import_tickets
    end

    it "uses origin_trip_id and appointment_time to find trips that are already being tracked" do
      create_csv(@input_folder, 'test8.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.stubs(:post).returns(stub_result)
      TripTicket.expects(:find_or_create_by_origin_trip_id_and_appointment_time).with(@minimum_trip_attributes[:origin_trip_id].to_s, @minimum_trip_attributes[:appointment_time]).returns(TripTicket.new)
      @adapter.import_tickets
    end

    it "creates new trips in the local database" do
      VCR.use_cassette('AdapterSync#import_tickets trip create test') do
        create_csv(@input_folder, 'test9.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
        @adapter.import_tickets
        TripTicket.first.ch_data_hash[:customer_last_name].must_equal 'Smith'
      end
    end

    it "updates existing trips on the Clearinghouse with PUT" do
      create_csv(@input_folder, 'test10.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      create(:trip_ticket, ch_id: 1379, origin_trip_id: @minimum_trip_attributes[:origin_trip_id], appointment_time: @minimum_trip_attributes[:appointment_time])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:put).once.returns(stub_result)
      @adapter.import_tickets
    end

    it "updates tracked trips in the local database with changes" do
      VCR.use_cassette('AdapterSync#import_tickets trip update test') do
        create_csv(@input_folder, 'test11.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
        @adapter.import_tickets
        trip = TripTicket.first
        trip.ch_data_hash[:customer_last_name].must_equal 'Smith'

        create_csv(@input_folder, 'test12.csv', @updated_trip_attributes.keys, [@updated_trip_attributes.values])
        @adapter.import_tickets
        trip.reload
        trip.ch_data_hash[:customer_last_name].must_equal 'Nohara'
      end
    end

    it "sends notifications for files that contained errors" do
      create_illegal_csv(@input_folder, 'test13.csv')
      AdapterNotification.any_instance.expects(:send).once
      @adapter.import_tickets
    end

  end
end
