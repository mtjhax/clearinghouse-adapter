require 'test_helper'
require 'fileutils'
require 'adapter_sync'
require 'support/import_helpers'

describe AdapterSync do
  include ImportHelpers

  before do
    @adapter = AdapterSync.new(import: { enabled: true })
    DatabaseCleaner.clean_with(:truncation)
  end

  describe AdapterSync, "#poll" do
    it "skips import step if import is not enabled" do
      @adapter.options[:import][:enabled] = false
      @adapter.expects(:import_tickets).never
      @adapter.poll
    end

    it "attempts to import flat files" do
      @adapter.expects(:import_tickets).once
      @adapter.poll
    end
  end

  describe AdapterSync, "#import_tickets" do
    before do
      @input_folder = 'tmp/_import_test'
      @output_folder = 'tmp/_import_test_out'
      FileUtils.mkpath @input_folder
      FileUtils.mkpath @output_folder
      @adapter = AdapterSync.new(import: { enabled: true, import_folder: @input_folder, completed_folder: @output_folder })
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

    after do
      remove_test_folders(@input_folder, @output_folder)
    end

    it "skips import if directory is not configured" do
      Import.any_instance.expects(:from_folder).never
      @adapter.options[:import][:import_folder] = nil
      @adapter.import_tickets
    end

    it "skips import if directory does not exist" do
      Import.any_instance.expects(:from_folder).never
      @adapter.options[:import][:import_folder] = 'tmp/__i/__dont/__exist'
      @adapter.import_tickets
    end

    it "disables import if directory is invalid" do
      @adapter.options[:import][:import_folder] = nil
      @adapter.import_tickets
      @adapter.options[:import][:enabled].must_equal false
    end

    it "sends each imported row to the Clearinghouse API" do
      file = create_csv(@input_folder, 'test1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      ApiClient.any_instance.expects(:post).once.returns([{ 'id' => 1379 }])
      @adapter.import_tickets
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
      ApiClient.any_instance.stubs(:post).returns([{ 'id' => 1379 }])
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
      ApiClient.any_instance.stubs(:post).returns([{ 'id' => 1379 }])
      @adapter.import_tickets
      TrackedTicket.count.must_equal 1
      tracked_ticket = TrackedTicket.first
      tracked_ticket.origin_trip_id.must_equal @minimum_trip_attributes[:origin_trip_id]
      tracked_ticket.clearinghouse_id.must_equal 1379
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

    # TODO ticket tracking and update features not yet added
    #it "updates the ticket on the clearinghouse if it already exists"
    #it "uses the local database to determine if a tracked ticket has been modified"
    # etc.

  end
end
