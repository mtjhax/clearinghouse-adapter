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
require 'support/file_helpers'
require_relative '../../processors/basic_import_processor'

describe ImportProcessor do
  include FileHelpers

  before do
    @input_folder = 'tmp/_import_test'
    @output_folder = 'tmp/_import_test_out'
    FileUtils.mkpath @input_folder
    FileUtils.mkpath @output_folder

    @options = { import_folder: @input_folder, completed_folder: @output_folder }
    @import_processor = ImportProcessor.new(nil, @options)

    DatabaseCleaner[:active_record, {model: ImportedFile}].clean_with(:truncation)
  end

  after do
    remove_test_folders(@input_folder, @output_folder)
  end
  
  describe "#process" do
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
      @address_attributes = {
        address_1: '5 Maple Brook Ln',
        city: 'Arlington'
      }
      @result_attributes = {
        actual_drop_off_time: "2000-01-01T02:45:00Z",
        actual_pick_up_time: "2000-01-01T02:45:00Z",
        base_fare: 123.0,
      }
      @array_field_attribute_columns = [
        "array_field_attribute_1",
        "array_field_attribute_2",
      ]
      @hash_field_attribute = {
        key_1: "hash_field_attribute_1",
        key_2: "hash_field_attribute_2",
      }
    end
    
    it "raises a runtime error if import directory is not configured" do
      @import_processor.options[:import_folder] = nil
      Proc.new { @import_processor.process() }.must_raise(RuntimeError)
    end

    it "raises a runtime error if import directory does not exist" do
      @import_processor.options[:import_folder] = 'tmp/__i/__dont/__exist'
      Proc.new { @import_processor.process() }.must_raise(RuntimeError)
    end

    it "skips files that were imported previously" do
      file = create_csv(@input_folder, 'skips_previously_imported_fles_test.csv', ['test','headers'], [['test','values']])
      FactoryGirl.create(:imported_file, file_name: file, modified: File.mtime(file), size: File.size(file), rows: 1)
      CsvImport.any_instance.expects(:from_folder).with(@input_folder, [file]).once.returns([[], []])
      @import_processor.process
    end
        
    it "returns the content of processed files as an array of hashes" do
      file = create_csv(@input_folder, 'returns_processedcontent_test-1.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      file = create_csv(@input_folder, 'returns_processed_content_test-2.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      results = @import_processor.process
      results.size.must_equal 2
      results[0][:customer_first_name].must_equal @minimum_trip_attributes[:customer_first_name]
      results[1][:customer_first_name].must_equal @minimum_trip_attributes[:customer_first_name]
    end
    
    it "ignores malformed CSV files" do
      good_file = create_csv(@input_folder, 'ignores_malformed_csv_test-good.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      bad_file = create_illegal_csv(@input_folder, 'ignores_malformed_csv_test-bad.csv')
      results = @import_processor.process
      results.size.must_equal 1
      results[0][:customer_first_name].must_equal @minimum_trip_attributes[:customer_first_name]
    end

    it "renames malformed CSV files" do
      bad_csv = create_illegal_csv(@input_folder, 'renames_malformed_csv_files_test.csv')
      @import_processor.process
      File.exist?(bad_csv).must_equal false
      File.exist?(File.join(bad_csv + '.error')).must_equal true
    end
    
    it "keeps track of import errors" do
      bad_csv = create_illegal_csv(@input_folder, 'tracks_import_errors_tests.csv')
      @import_processor.process
      @import_processor.errors.size.must_equal 1
      @import_processor.errors.first.must_include bad_csv
    end

    it "only tries to import files with an extension of .txt or .csv" do
      csv_file = create_csv(@input_folder, 'only_imports_known_extensions_tests.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      txt_file = create_csv(@input_folder, 'only_imports_known_extensions_tests.txt', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      foo_file = create_csv(@input_folder, 'only_imports_known_extensions_tests.foo', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      results = @import_processor.process
      results.size.must_equal 2
      results[0][:customer_first_name].must_equal @minimum_trip_attributes[:customer_first_name]
      results[1][:customer_first_name].must_equal @minimum_trip_attributes[:customer_first_name]
    end
    
    it "supports import of nested customer_address, pick_up_location, drop_off_location, and trip_result objects" do
      attrs = @minimum_trip_attributes
        .merge(convert_nested_object_hash_to_columns(@address_attributes, :customer_address))
        .merge(convert_nested_object_hash_to_columns(@address_attributes, :pick_up_location))
        .merge(convert_nested_object_hash_to_columns(@address_attributes, :drop_off_location))
        .merge(convert_nested_object_hash_to_columns(@result_attributes, :trip_result))
      create_csv(@input_folder, 'supports_nested_objects_test.csv', attrs.keys, [attrs.values])
      results = @import_processor.process
      results.size.must_equal 1
      results[0][:customer_address_attributes][:address_1].must_equal @address_attributes[:address_1]
      results[0][:pick_up_location_attributes][:address_1].must_equal @address_attributes[:address_1]
      results[0][:drop_off_location_attributes][:address_1].must_equal @address_attributes[:address_1]
      results[0][:trip_result_attributes][:base_fare].must_equal @result_attributes[:base_fare].to_s
    end
    
    it "combines separate columns of customer_eligibility_factors, customer_mobility_factors, customer_service_animals, and trip_funders fields into an array" do
      attrs = @minimum_trip_attributes
        .merge(convert_array_attribute_to_columns(@array_field_attribute_columns, :customer_eligibility_factors))
        .merge(convert_array_attribute_to_columns(@array_field_attribute_columns, :customer_mobility_factors))
        .merge(convert_array_attribute_to_columns(@array_field_attribute_columns, :customer_service_animals))
        .merge(convert_array_attribute_to_columns(@array_field_attribute_columns, :trip_funders))
      create_csv(@input_folder, 'combines_array_columns_test.csv', attrs.keys, [attrs.values])
      results = @import_processor.process
      results.size.must_equal 1
      results[0][:customer_eligibility_factors][0].must_equal @array_field_attribute_columns[0]
      results[0][:customer_mobility_factors][0].must_equal @array_field_attribute_columns[0]
      results[0][:customer_service_animals][0].must_equal @array_field_attribute_columns[0]
      results[0][:trip_funders][0].must_equal @array_field_attribute_columns[0]
    end

    it "combines separate columns of customer_identifiers field into a hash" do
      attrs = @minimum_trip_attributes.merge(convert_hash_attribute_to_columns(@hash_field_attribute, :customer_identifiers))
      create_csv(@input_folder, 'combines_hash_columns_test.csv', attrs.keys, [attrs.values])
      results = @import_processor.process
      results.size.must_equal 1
      results[0][:customer_identifiers].keys[0].must_equal @hash_field_attribute.keys[0].to_s
      results[0][:customer_identifiers].values[0].must_equal @hash_field_attribute.values[0]
      results[0][:customer_identifiers].keys[1].must_equal @hash_field_attribute.keys[1].to_s
      results[0][:customer_identifiers].values[1].must_equal @hash_field_attribute.values[1]
    end

    it "converts dates formatted as mm/dd/yyyy to dd/mm/yyyy" do
      create_csv(@input_folder, 'converts_date_format_test.csv', @minimum_trip_attributes.keys, [@minimum_trip_attributes.values])
      results = @import_processor.process
      results[0][:customer_dob].must_equal "02/01/1955"
    end
  end
  
  describe "#finalize" do
    it "tracks imported files to prevent reimport" do
      file = 'tracks_imported_files_test.csv'
      file_size = 42
      file_time = Time.now
      results = [{ file_name: file, size: file_size, modified: file_time, error: false, rows: 1 }]
      @import_processor.instance_variable_set(:@import_results, results)
      
      @import_processor.finalize
      ImportedFile.count.must_equal 1
      imported_file = ImportedFile.first
      imported_file.file_name.must_equal file
      imported_file.size.must_equal file_size
      imported_file.modified.must_equal file_time
      imported_file.rows.must_equal 1
    end
    
    it "does not track files that could not be imported" do
      file = 'does_not_track_bad_files.csv'
      file_size = 42
      file_time = Time.now
      results = [{ file_name: file, size: file_size, modified: file_time, error: true }]
      @import_processor.instance_variable_set(:@import_results, results)
      
      @import_processor.finalize
      ImportedFile.count.must_equal 0
    end

    it "moves processed files to the output folder" do
      file = create_empty_files(@input_folder, 'moves_processed_files.csv')[0]
      file_size = File.size(file)
      file_time = File.mtime(file)
      results = [{ file_name: file, size: file_size, modified: file_time, error: false, rows: 1 }]
      @import_processor.instance_variable_set(:@import_results, results)
      
      @import_processor.finalize

      File.exist?(file).must_equal false
      File.exist?(File.join(@output_folder, 'moves_processed_files.csv')).must_equal true
    end
  end
  
  private
  
  def convert_nested_object_hash_to_columns(hash, attribute_name)
    columns = {}
    hash.each do |k,v|
      columns["#{attribute_name}_#{k}"] = v
    end
    columns
  end

  def convert_hash_attribute_to_columns(hash, attribute_name)
    columns = {}
    hash.each_with_index do |(k,v), i|
      columns["#{attribute_name}_#{i + 1}_key"] = k
      columns["#{attribute_name}_#{i + 1}_value"] = v
    end
    columns
  end
  
  def convert_array_attribute_to_columns(array, attribute_name)
    columns = {}
    array.each_with_index do |v, i|
      columns["#{attribute_name}_#{i + 1}"] = v
    end
    columns
  end
end
