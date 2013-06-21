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
        export: { enabled: true, export_folder: @export_folder }
    }
    @adapter = AdapterSync.new(@adapter_options)
    DatabaseCleaner.clean_with(:truncation)
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
      @adapter.stubs(:get_updated_clearinghouse_trips).returns([ {'this' => 'hash', 'lacks' => 'an id key'} ])
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
    it "requests trips updated since most recent tracked updated_at time"
    it "requests all trips if there are no locally tracked trips"
    it "stores new and modified trips in the trip_updates instance variable"
    it "stores new and modified trip claims in the claim_updates instance variable"
    it "stores new and modified trip comments in the comment_updates instance variable"
    it "stores new and modified trip results in the result_updates instance variable"
  end

  describe AdapterSync, "#export_changes" do
    it "raises a runtime error if export directory is not configured" do
      @adapter.options[:export][:export_folder] = nil
      Proc.new { @adapter.export_changes }.must_raise(RuntimeError)
    end

    it "raises a runtime error if export directory does not exist" do
      @adapter.options[:export][:export_folder] = 'tmp/__i/__dont/__exist'
      Proc.new { @adapter.export_changes }.must_raise(RuntimeError)
    end

    it "outputs new and modified trip tickets to a CSV file"
    it "outputs new and modified trip claims to a CSV file"
    it "outputs new and modified trip comments to a CSV file"
    it "outputs new and modified trip results to a CSV file"
  end

  describe AdapterSync, "#report_sync_errors" do
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
        appointment_time: '10:00',
        requested_drop_off_time: '13:00',
        customer_information_withheld: false,
        scheduling_priority: 'pickup'
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
      file = create_csv(@input_folder, 'test.csv', ['test','headers'], [['test','values']])
      create(:imported_file, file_name: file, modified: File.mtime(file), size: File.size(file), rows: 1)
      Import.any_instance.expects(:from_folder).with(@input_folder, @output_folder, [file]).once.returns([])
      @adapter.import_tickets
    end

    it "tracks imported files to prevent reimport" do
      file = create_csv(@input_folder, 'test1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
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

    it "tracks imported rows to prevent reimport" do
      file = create_csv(@input_folder, 'test1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_tickets
      TripTicket.count.must_equal 1
      trip = TripTicket.first
      trip.origin_trip_id.must_equal @minimum_trip_attributes[:origin_trip_id]
      trip.ch_id.must_equal 1379
    end

    it "marks rows as errors if they do not contain an origin_trip_id" do
      attrs = @minimum_trip_attributes.tap {|h| h.delete(:origin_trip_id) }
      file = create_csv(@input_folder, 'test1.csv', attrs.keys, [attrs.values])
      @adapter.import_tickets
      ImportedFile.count.must_equal 1
      imported_file = ImportedFile.first
      imported_file.file_name.must_equal file
      imported_file.rows.must_equal 1
      imported_file.row_errors.must_equal 1
    end

    it "marks rows as errors if they cannot be sent to the Clearinghouse API" do
      file = create_csv(@input_folder, 'test1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      ApiClient.any_instance.stubs(:post).raises(RuntimeError, "This row blew up the API")
      @adapter.import_tickets
      ImportedFile.count.must_equal 1
      imported_file = ImportedFile.first
      imported_file.rows.must_equal 1
      imported_file.row_errors.must_equal 1
    end

    it "supports import of nested location objects"
    it "supports import of nested trip_result object"
    it "uses origin_trip_id and appointment_time to find trips that are already being tracked"

    it "sends new trips to the Clearinghouse API with POST" do
      file = create_csv(@input_folder, 'test1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_tickets
    end

    it "creates new trips in the local database"
    it "updates existing trips on the Clearinghouse with PUT"
    it "updates tracked trips in the local database with changes"
    it "sends notifications for files that contained errors"
  end
end
