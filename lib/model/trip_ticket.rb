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

require 'maps_attributes'

class TripTicket < ActiveRecord::Base

  maps_attributes ['*', 'ch_data'],
                  ['id', 'ch_id'],
                  ['updated_at', 'ch_updated_at'],
                  'is_originated',
                  'origin_trip_id',
                  'appointment_time'

  # Attributes:
  # t.integer :ch_id                  # matching ID on the Clearinghouse
  # t.datetime :ch_updated_at         # to track the latest change we have seen
  # t.boolean :is_originated          # true if originated by current provider
  #
  # # originator may reuse an origin_trip_id with a new appointment_time, this should be a separate trip on the CH
  # # track these two fields so when importing trips we can determine if trips should be created or updated
  # t.integer :origin_trip_id
  # t.datetime :appointment_time
  #
  # t.text :ch_data                   # the entire clearinghouse ticket stored as JSON
  # t.timestamps

  def synced?
    !ch_id.nil?
  end

  def claims
    ch_data_hash.trip_claims
  end

  def result
    ch_data_hash.trip_result
  end

  def comments
    ch_data_hash.trip_ticket_comments
  end

end
