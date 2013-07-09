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
require 'api_client'

describe ApiClient do

  # the following values can be changed to match available data if a new VCR cassette needs to be recorded:
  EXAMPLE_TRIP_ID = 1
  NUM_COMMENTS = 2
  EXAMPLE_COMMENT_ID = 2
  EXAMPLE_USER_ID = 4

  before do
    @api = ApiClient.new({
      api_base_url: 'http://localhost:3000/api',
      api_version: 'v1',
      api_key: '3d0fdf48c058b1f43bb63da689d1f8bd',
      api_private_key: '083ad201d16698b8bc945d8ddd2d759c'
    })
    VCR.insert_cassette "api_client_test"
  end

  after do
    VCR.eject_cassette
  end

  it "allows lists of resources to be retrieved with GET" do
    trip_tickets = @api.get('trip_tickets')
    trip_tickets.must_be_kind_of(Array)
    trip_tickets.length.must_be :>, 0
    trip_tickets[0][:id].must_be_kind_of(Integer)
    trip_tickets[0][:origin_provider_id].must_be_kind_of(Integer)
  end

  it "allows individual resources to be retrieved with GET" do
    trip_ticket = @api.get("trip_tickets/#{EXAMPLE_TRIP_ID}")
    trip_ticket[:id].must_equal EXAMPLE_TRIP_ID
  end

  it "works with nested resources" do
    comments = @api.get("trip_tickets/#{EXAMPLE_TRIP_ID}/trip_ticket_comments")
    comments.must_be_kind_of(Array)
    comments.length.must_equal NUM_COMMENTS
    comments.map{|c| c[:id] }.must_include(EXAMPLE_COMMENT_ID)
  end

  it "returns an object that can be used to request nested resources" do
    comments = @api.get("trip_tickets/#{EXAMPLE_TRIP_ID}").get('trip_ticket_comments')
    comments.must_be_kind_of(Array)
    comments.length.must_equal NUM_COMMENTS
  end

  it "returns simple hashes if :raw option is used" do
    @api.options[:raw] = true
    trip_ticket = @api.get([:trip_tickets, EXAMPLE_TRIP_ID])
    trip_ticket.must_be_kind_of(Hash)
  end

  it "accepts resources defined as symbols" do
    trip_tickets = @api.get(:trip_tickets)
    trip_tickets.must_be_kind_of(Array)
    trip_tickets.length.must_be :>, 0
  end

  it "accepts resources defined as arrays" do
    comments = @api.get(['trip_tickets', EXAMPLE_TRIP_ID, :trip_ticket_comments])
    comments.must_be_kind_of(Array)
    comments.length.must_equal NUM_COMMENTS
  end

  it "accepts resources defined as nested arrays" do
    comment = @api.get(['trip_tickets', EXAMPLE_TRIP_ID, [:trip_ticket_comments, EXAMPLE_COMMENT_ID]])
    comment.must_be_kind_of(ApiClient)
    comment[:id].must_equal EXAMPLE_COMMENT_ID
  end

  it "allows resources to be created with POST" do
    comment_attrs = { user_id: EXAMPLE_USER_ID, body: "Hi there" }
    comment = @api.post("trip_tickets/#{EXAMPLE_TRIP_ID}/trip_ticket_comments", comment_attrs)
    comment.must_be_kind_of(ApiClient)
    comment[:body].must_equal "Hi there"
  end

  it "allows resources to be updated with PUT" do
    trip_attrs = { customer_first_name: 'Slim', customer_last_name: 'Shady' }
    trip_ticket = @api.put("trip_tickets/#{EXAMPLE_TRIP_ID}", trip_attrs)
    trip_ticket.must_be_kind_of(ApiClient)
    trip_ticket[:customer_first_name].must_equal trip_attrs[:customer_first_name]
    trip_ticket[:customer_last_name].must_equal trip_attrs[:customer_last_name]
  end

  it "allows resources to be deleted with DELETE" do
    # Clearinghouse currently does not allow deletion of anything so confirm that it raises proper exception
    Proc.new do
      @api.delete("trip_tickets/#{EXAMPLE_TRIP_ID}")
    end.must_raise(RestClient::MethodNotAllowed)
  end

end
