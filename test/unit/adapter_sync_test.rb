# Copyright 2015 Ride Connection
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
require 'adapter_sync'

describe AdapterSync do
  before do
    AdapterNotification.any_instance.stubs(:send)
    ExportProcessor.any_instance.stubs(:process)
    ImportProcessor.any_instance.stubs(:process).returns([])
    ImportProcessor.any_instance.stubs(:finalize)

    @adapter = AdapterSync.new({})

    DatabaseCleaner.clean_with(:truncation)
  end
  
  describe "#initialize" do
    it "passes along any processor options" do
      adapter_options = {
        import: {
          options: {
            foo: :bar
          }
        },
        export: {
          options: {
            foz: :baz
          }
        },
      }
      adapter = AdapterSync.new(adapter_options)
      
      assert_equal adapter_options[:import][:options], adapter.import_processor.options
      assert_equal adapter_options[:export][:options], adapter.export_processor.options
    end
  end

  describe "#poll" do
    it "calls replicate_clearinghouse, export_tickets, and import_tickets" do
      @adapter.stubs(:get_updated_clearinghouse_trips).returns([])
      @adapter.expects(:replicate_clearinghouse).once
      @adapter.expects(:export_tickets).once
      @adapter.expects(:import_tickets).once
      @adapter.poll
    end
        
    it "handles any errors raised during polling by rolling back all database transactions, sending a notification, and then re-raising the error" do
      # #get_updated_clearinghouse_trips records all new trips in the
      # database, therefore TripTicket.count would == 1 at the end
      new_trip = ApiClient.new
      new_trip.stubs(:data).returns({id: 2})
      @adapter.stubs(:get_updated_clearinghouse_trips).returns([new_trip])
      
      # Raise an error
      @adapter.stubs(:import_tickets).raises
      
      # Ensure that a notification is sent, the database is rolled 
      # back, and the error is re-raised
      AdapterNotification.any_instance.expects(:send).once
      Proc.new { @adapter.poll }.must_raise(RuntimeError)
      TripTicket.count.must_equal 0
    end
  end

  describe "#replicate_clearinghouse" do
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
    
    describe "trip pre-processing" do
      before do
        @existing_trip_hash = {
          id: 1,
          trip_claims: [{id: 1}],
          trip_ticket_comments: [{id: 1}],
          trip_result: {id: 1},
        }
        TripTicket.new.map_attributes(@existing_trip_hash).save!
        existing_trip = ApiClient.new
        existing_trip.stubs(:data).returns(@existing_trip_hash)
        
        @new_trip_hash = {
          id: 2,
          trip_claims: [{id: 2}],
          trip_ticket_comments: [{id: 2}],
          trip_result: {id: 2},
        }
        new_trip = ApiClient.new
        new_trip.stubs(:data).returns(@new_trip_hash)
        
        @adapter.stubs(:get_updated_clearinghouse_trips).returns([ existing_trip, new_trip ])
      end
      
      it "adds association hashes to each trip when not specified" do
        sparse_trip = ApiClient.new
        sparse_trip.stubs(:data).returns(@new_trip_hash.except(:trip_claims, :trip_ticket_comments, :trip_result))
        @adapter.stubs(:get_updated_clearinghouse_trips).returns([ sparse_trip ])

        @adapter.replicate_clearinghouse
        
        trip_hash = @adapter.exported_trips.first
        refute trip_hash[:trip_claims].nil?
        refute trip_hash[:trip_ticket_comments].nil?
        refute trip_hash[:trip_result].nil?
      end

      it "marks new trip ticket records and associated objects" do
        @adapter.replicate_clearinghouse

        new_trip_hash = @adapter.exported_trips.last
        assert_equal true, new_trip_hash[:new_record]
        assert_equal true, new_trip_hash[:trip_claims].first[:new_record]
        assert_equal true, new_trip_hash[:trip_ticket_comments].first[:new_record]
        assert_equal true, new_trip_hash[:trip_result][:new_record]
      end

      it "marks new associated objects on previously stored trip ticket records" do
        @existing_trip_hash[:trip_claims] << {id: 2}
        @existing_trip_hash[:trip_ticket_comments] << {id: 2}
        modified_trip = ApiClient.new
        modified_trip.stubs(:data).returns(@existing_trip_hash)
        @adapter.stubs(:get_updated_clearinghouse_trips).returns([ modified_trip ])

        @adapter.replicate_clearinghouse
        
        modified_trip_hash = @adapter.exported_trips.first
        assert_equal false, modified_trip_hash[:new_record]
        assert_equal false, modified_trip_hash[:trip_claims].first[:new_record]
        assert_equal true,  modified_trip_hash[:trip_claims].last[:new_record]
        assert_equal false, modified_trip_hash[:trip_ticket_comments].first[:new_record]
        assert_equal true,  modified_trip_hash[:trip_ticket_comments].last[:new_record]
      end
    
      it "stores new trip ticket info to the database" do
        @adapter.replicate_clearinghouse
        assert @new_trip_hash.with_indifferent_access == TripTicket.find_by_ch_id(@new_trip_hash[:id]).ch_data_hash.with_indifferent_access
      end
    
      it "updates previously stored trip ticket records in the database" do
        modified_trip_hash = @existing_trip_hash.merge({new_field: "modified"})
        modified_trip = ApiClient.new
        modified_trip.stubs(:data).returns(modified_trip_hash)
        @adapter.stubs(:get_updated_clearinghouse_trips).returns([ modified_trip ])

        @adapter.replicate_clearinghouse
        assert modified_trip_hash.with_indifferent_access == TripTicket.find_by_ch_id(modified_trip_hash[:id]).ch_data_hash.with_indifferent_access
      end
    end

    it "stores all valid trip updates in @exported_trips" do
      bad_trip = ApiClient.new
      bad_trip.stubs(:data).returns({'this' => 'hash', 'lacks' => 'an id key'})

      good_trip = ApiClient.new
      good_trip.stubs(:data).returns({'this' => 'hash', 'has' => 'an id key', 'id' => '1'})

      @adapter.stubs(:get_updated_clearinghouse_trips).returns([ good_trip, bad_trip ])
      @adapter.replicate_clearinghouse
      assert_equal 1, @adapter.exported_trips.size
    end
    
    it "reports any errors encountered durring pre-processing" do
      AdapterNotification.any_instance.expects(:send).once
      @adapter.stubs(:errors).returns(["error"])
      @adapter.replicate_clearinghouse
    end
  end
  
  describe "#export_tickets" do
    before do
      @adapter.options[:export][:enabled] = true
    end
      
    it "calls the export processor step if enabled and passes in the updated trips" do
      @adapter.exported_trips = [{'id' => '1'}]
      @adapter.export_processor.expects(:process).with(@adapter.exported_trips).once
      @adapter.export_tickets
    end

    it "skips export step if not enabled" do
      @adapter.options[:export][:enabled] = false
      @adapter.export_processor.expects(:process).never
      @adapter.export_tickets
    end

    it "reports any errors logged by the export processor" do
      @adapter.export_processor.stubs(:errors).returns(["error"])
      AdapterNotification.any_instance.expects(:send).once
      @adapter.export_tickets
    end
  end

  describe "#import_tickets" do
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
        scheduling_priority: 'pickup',
      }
      @adapter.import_processor.stubs(:process).returns([@minimum_trip_attributes])
      @adapter.options[:import][:enabled] = true
    end
  
    it "calls the import processor step if enabled" do
      @adapter.import_processor.expects(:process).once.returns([])
      @adapter.import_tickets
    end

    it "skips import step if not enabled" do
      @adapter.options[:import][:enabled] = false
      @adapter.import_processor.expects(:process).never
      @adapter.import_tickets
    end
  
    it "reports any errors logged by the import processor" do
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_processor.stubs(:errors).returns(["error"])
      AdapterNotification.any_instance.expects(:send).once
      @adapter.import_tickets
    end
  
    it "sends new trips to the Clearinghouse API with POST" do
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_tickets
    end
    
    it "uses origin_trip_id and appointment_time to find trips that are already being tracked" do
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.stubs(:post).returns(stub_result)
      TripTicket.expects(:find_or_create_by).with(origin_trip_id: @minimum_trip_attributes[:origin_trip_id], appointment_time: @minimum_trip_attributes[:appointment_time]).returns(TripTicket.new)
      @adapter.import_tickets
    end
  
    it "creates new trips in the local database" do
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      stub_result.stubs(:data).returns(@minimum_trip_attributes.merge({id: 1379}))
      ApiClient.any_instance.stubs(:post).returns(stub_result)
      @adapter.import_tickets
      TripTicket.first.ch_data_hash[:customer_last_name].must_equal 'Smith'
    end
  
    it "updates existing trips on the Clearinghouse with PUT" do
      create(:trip_ticket, ch_id: 1379, origin_trip_id: @minimum_trip_attributes[:origin_trip_id], appointment_time: @minimum_trip_attributes[:appointment_time])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:put).once.returns(stub_result)
      @adapter.import_tickets
    end
  
    it "updates tracked trips in the local database with changes" do
      create(:trip_ticket, ch_id: 1379, origin_trip_id: @minimum_trip_attributes[:origin_trip_id], appointment_time: @minimum_trip_attributes[:appointment_time], ch_data: {customer_last_name: "Jones"})
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      stub_result.stubs(:data).returns(@minimum_trip_attributes)
      ApiClient.any_instance.stubs(:put).returns(stub_result)
      @adapter.import_tickets
      TripTicket.first.ch_data_hash[:customer_last_name].must_equal 'Smith'
    end
    
    it "calls ImportProcessor#finalize after processing" do
      @adapter.import_processor.stubs(:process).returns([])
      @adapter.import_processor.expects(:finalize).with([], [], []).once()
      @adapter.import_tickets
    end

    it "passes all imported rows to ImportProcessor#finalize after processing" do
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_processor.expects(:finalize).with([@minimum_trip_attributes.with_indifferent_access], [], []).once()
      @adapter.import_tickets
    end

    it "passes malformed rows to ImportProcessor#finalize after processing" do
      bad_hash = @minimum_trip_attributes.merge({origin_trip_id: nil})
      @adapter.import_processor.stubs(:process).returns([bad_hash])
      stub_result = ApiClient.new.tap {|result| result[:id] = 1379 }
      @adapter.import_processor.expects(:finalize).with([], [bad_hash.with_indifferent_access], []).once()
      @adapter.import_tickets
    end

    it "passes rows that didn't return as expected from the API to ImportProcessor#finalize after processing" do
      stub_result = ApiClient.new
      ApiClient.any_instance.expects(:post).once.returns(stub_result)
      @adapter.import_processor.expects(:finalize).with([], [], [@minimum_trip_attributes.with_indifferent_access]).once()
      @adapter.import_tickets
    end
  end
end
