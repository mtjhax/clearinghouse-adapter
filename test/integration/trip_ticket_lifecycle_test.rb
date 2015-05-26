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
require 'support/file_helpers'

describe "trip ticket life cycles" do
  include FileHelpers

  EXPORT_FOLDER = 'tmp/export_test'
  IMPORT_FOLDER = 'tmp/import_test'
  COMPLETED_FOLDER = 'tmp/import_test_completed'
  TEST_FOLDERS = [EXPORT_FOLDER, IMPORT_FOLDER, COMPLETED_FOLDER]

  let(:provider_1_api_settings) {{
    api_base_url: 'http://localhost:3000/api',
    api_version: 'v1',
    api_key: 'fb3c85be27b6e810925d75b3d9f08f25',
    api_private_key: '4a17d8b3437a16e0d526c5355449afef'
  }}

  let(:provider_2_api_settings) {{
    api_base_url: 'http://localhost:3000/api',
    api_version: 'v1',
    api_key: 'c8b6abce74cd58efd3b7d0a2045fbf85',
    api_private_key: '48ecb3ed3abe2dbd238e472b48a035db'
  }}

  let(:base_adapter_settings) {{
    export: {
      enabled: true,
      processor: 'basic_export_processor/basic_export_processor.rb',
      options: { export_folder: EXPORT_FOLDER }
    },
    import: {
      enabled: true,
      processor: 'basic_import_processor/basic_import_processor.rb',
      options: {
        import_folder: IMPORT_FOLDER,
        completed_folder: COMPLETED_FOLDER
      }
    }
  }}

  let(:provider_1_api) { ApiClient.new(provider_1_api_settings) }
  let(:provider_2_api) { ApiClient.new(provider_2_api_settings) }
  let(:provider_1_adapter) { AdapterSync.new(base_adapter_settings.merge({ api: provider_1_api_settings })) }
  let(:provider_2_adapter) { AdapterSync.new(base_adapter_settings.merge({ api: provider_2_api_settings })) }

  let(:minimum_trip_attributes) {{
    origin_trip_id: 'originator-trip-id-12345',
    origin_customer_id: 222,
    customer_first_name: 'Bob',
    customer_last_name: 'Smith',
    customer_dob: '1/2/1955',
    customer_primary_phone: '222-333-4444',
    customer_seats_required: 1,
    requested_pickup_time: '09:00',
    appointment_time: '2016-01-01T09:00:00Z',
    requested_drop_off_time: '13:00',
    customer_information_withheld: false,
    scheduling_priority: 'pickup'
  }}

  let(:minimum_claim_attributes) {{
    proposed_pickup_time: '2016-01-01T09:00:00Z',
    status: :pending
  }}

  before do
    # do not allow Adapter to send out email notifications
    AdapterNotification.any_instance.stubs(:send)

    # create separate test import/export folders for Adapter
    TEST_FOLDERS.each {|f| FileUtils.mkpath f }

    provider_1_adapter  # instantiate just to open database
    DatabaseCleaner.clean_with(:truncation)
  end

  after do
    remove_test_folders *TEST_FOLDERS
  end

  describe "rescinded tickets" do
    # scenario 1:
    # set up an import file and run Adapter sync to push it up to the Clearinghouse
    # get most recent created trip so we know its Clearinghouse ID for reference
    # set up an import file with the same ticket and status updated to rescinded
    # run Adapter sync to import the updated trip
    # trip ticket in CH should now be rescinded

    it "rescinds trip in the Clearinghouse if import indicates they are rescinded" do
      VCR.use_cassette 'trip_ticket_lifecycle_test_1', record: :once, match_requests_on: [:method, :path] do
        # set up an import file and run Adapter sync to push it up to the Clearinghouse
        create_csv IMPORT_FOLDER, 'new_ticket.csv', minimum_trip_attributes.keys, [minimum_trip_attributes.values]
        provider_1_adapter.poll

        # get most recent created trip so we know its Clearinghouse ID for reference
        new_trip = TripTicket.order('created_at DESC').first
        new_trip.ch_id.must_be_kind_of(Integer)

        # set up an import file with the same ticket and status updated to rescinded
        # note that the import file does not have the ch_id, provider systems are not expected to import
        # and maintain clearinghouse IDs -- trips are matched on provider ID + appointment date
        attrs = minimum_trip_attributes.merge(status: 'rescinded')
        create_csv IMPORT_FOLDER, 'rescinded_ticket.csv', attrs.keys, [attrs.values]

        # run Adapter sync to import the updated trip
        provider_1_adapter.poll

        # trip ticket in Adapter local data should now be marked rescinded
        new_trip.reload
        new_trip.ch_data_hash.try(:[], :rescinded).must_equal true

        # trip ticket in CH should now be rescinded
        trip = provider_1_api.get("trip_tickets/#{new_trip.ch_id}")
        trip.must_be_kind_of(ApiClient)
        trip[:status].must_equal "Rescinded"
      end
    end

    # scenario 2:
    # put a trip ticket in the clearinghouse and get back its ID for reference
    # have a second provider create a claim on the trip ticket
    # have the first provider approve the claim
    # run Adapter sync for second provider to download the approved trip
    # have first provider rescind the trip
    # run Adapter sync for second provider
    # second provider's trip should have status:rescinded
    # because it was approved, claim will not be rescinded but a trip 'cancelled' result should be added
    # make sure trip is exported for second provider with these values

    it "exports rescinded ticket status for a claimant" do
      VCR.use_cassette 'trip_ticket_lifecycle_test_2', record: :once, match_requests_on: [:method, :path] do
        # put a trip ticket in the clearinghouse and get back its ID for reference
        # note that Adapter is not multi-tenant so we need to only use AdapterSync for provider 2
        new_trip = provider_1_api.post 'trip_tickets', minimum_trip_attributes
        new_trip[:id].must_be_kind_of Integer

        # have a second provider create a claim on the trip ticket
        # we will also do this via the API since the Adapter does not currently import claims
        claim = provider_2_api.post("trip_tickets/#{new_trip[:id]}/trip_claims", minimum_claim_attributes)
        claim[:id].must_be_kind_of Integer

        # have the first provider approve the claim
        approved = provider_1_api.put("trip_tickets/#{new_trip[:id]}/trip_claims/#{claim[:id]}/approve", {})
        approved.must_be_kind_of ApiClient
        approved[:status].must_equal 'approved'

        # run Adapter sync for second provider to download the approved trip
        provider_2_adapter.poll

        adapter_trip = TripTicket.order('created_at DESC').first
        adapter_trip.ch_id.must_be_kind_of Integer
        adapter_trip.ch_id.must_equal new_trip[:id]

        claims = adapter_trip.ch_data_hash.try :[], :trip_claims
        claims.length.must_equal 1
        claims[0][:id].must_equal claim[:id]
        claims[0][:is_claimant].must_equal true
        claims[0][:status].must_equal 'approved'

        # have first provider rescind the trip
        rescinded_trip = provider_1_api.put "trip_tickets/#{new_trip[:id]}/rescind", {}
        rescinded_trip[:status].must_equal 'Rescinded'

        # run Adapter sync for second provider
        provider_2_adapter.poll

        # second provider's trip should have status:rescinded
        adapter_trip.reload
        adapter_trip.ch_data_hash[:status].must_equal 'Rescinded'

        # because it was approved, claim will not be rescinded but a trip 'cancelled' result should be added
        adapter_trip.ch_data_hash[:trip_result].wont_be_nil
        adapter_trip.ch_data_hash[:trip_result][:outcome].must_equal 'Cancelled'

        # TODO consider reading in the export files to make sure trip was exported for second provider with proper status
        #      (this has been manually verified)
      end
    end

  end
end
