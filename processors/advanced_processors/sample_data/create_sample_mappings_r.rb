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

# This utility script generates an example of advanced import and export processor mappings
# in YAML format, since it is easier to write them out in Ruby.

require 'yaml'

SAMPLE_IMPORT_MAPPING = {
  __accept_unmapped__:                true,
  clearinghouse_trip_id:              { ignore: true },
  trip_id:                            :origin_trip_id,
  status:                             { ignore: true },
  provider:                           { ignore: true },
  customer_id:                        :origin_customer_id,
  customer_middle_initial:            :customer_middle_name,
  customer_home_address_id:           { ignore: true },
  customer_home_address_type:         [ :customer_address_attributes, :address_type ],
  customer_home_telephone:            { prepend: [[ :customer_address_attributes, :phone_number ], ' ' ]},
  customer_home_telephone_extension:  { append: [[ :customer_address_attributes, :phone_number ], ' ' ]},
  customer_home_common_name:          [ :customer_address_attributes, :common_name ],
  customer_home_address_1:            [ :customer_address_attributes, :address_1 ],
  customer_home_address_2:            [ :customer_address_attributes, :address_2 ],
  customer_home_city:                 [ :customer_address_attributes, :city ],
  customer_home_county:               [ :customer_address_attributes, :jurisdiction ],
  customer_home_state:                [ :customer_address_attributes, :state ],
  customer_home_zip:                  [ :customer_address_attributes, :zip ],
  customer_home_latitude:             [ :customer_address_attributes, :latitude ],
  customer_home_longitude:            [ :customer_address_attributes, :longitude ],
  customer_home_edge_id:              { key_values: [ :additional_data, ',', :customer_home_edge_id ]},
  customer_sex:                       :customer_gender,
  customer_internal_id:               { key_values: [ :customer_identifiers, ',', :rc_customer_id ]},
  customer_load_time:                 :customer_boarding_time,
  customer_unload_time:               :customer_deboarding_time,
  customer_mobility_requirement:      :customer_service_level,
  customer_assistance_needs:          { list: [ :customer_mobility_factors, '|' ]},
  customer_eligibility:               { list: [ :customer_eligibility_factors, '|' ]},
  attendant_mobility:                 { key_values: [ :additional_data, ',', :attendant_mobility ]},
  guest_mobility:                     { key_values: [ :additional_data, ',', :guest_mobility ]},
  pickup_address_id:                  { ignore: true },
  pickup_address_type:                [ :pick_up_location_attributes, :address_type ],
  pickup_telephone:                   { prepend: [[ :pick_up_location_attributes, :phone_number ], ' ' ]},
  pickup_telephone_extension:         { append: [[ :pick_up_location_attributes, :phone_number ], ' ' ]},
  pickup_common_name:                 [ :pick_up_location_attributes, :common_name ],
  pickup_address_1:                   [ :pick_up_location_attributes, :address_1 ],
  pickup_address_2:                   [ :pick_up_location_attributes, :address_2 ],
  pickup_city:                        [ :pick_up_location_attributes, :city ],
  pickup_county:                      [ :pick_up_location_attributes, :jurisdiction ],
  pickup_state:                       [ :pick_up_location_attributes, :state ],
  pickup_zip:                         [ :pick_up_location_attributes, :zip ],
  pickup_latitude:                    [ :pick_up_location_attributes, :latitude ],
  pickup_longitude:                   [ :pick_up_location_attributes, :longitude ],
  pickup_home_edge_id:                { key_values: [ :additional_data, ',', :pickup_edge_id ]},
  drop_off_address_id:                { ignore: true },
  drop_off_address_type:              [ :drop_off_location_attributes, :address_type ],
  dropoff_telephone:                  { prepend: [[ :drop_off_location_attributes, :phone_number ], ' ' ]},
  drop_off_telephone_extension:       { append: [[ :drop_off_location_attributes, :phone_number ], ' ' ]},
  drop_off_common_name:               [ :drop_off_location_attributes, :common_name ],
  drop_off_address_1:                 [ :drop_off_location_attributes, :address_1 ],
  drop_off_address_2:                 [ :drop_off_location_attributes, :address_2 ],
  drop_off_city:                      [ :drop_off_location_attributes, :city ],
  drop_off_county:                    [ :drop_off_location_attributes, :jurisdiction ],
  drop_off_state:                     [ :drop_off_location_attributes, :state ],
  drop_off_zip:                       [ :drop_off_location_attributes, :zip ],
  drop_off_latitude:                  [ :drop_off_location_attributes, :latitude ],
  drop_off_longitude:                 [ :drop_off_location_attributes, :longitude ],
  drop_off_home_edge_id:              { key_values: [ :additional_data, ',', :drop_off_edge_id ]},
  requested_pickup_date:              { ignore: true },
  requested_pickup_time:              true,
  requested_drop_off_date:            { ignore: true },
  requested_drop_off_time:            { and: [ :requested_drop_off_time, :appointment_time ]},
  early_window:                       :time_window_before,
  late_window:                        :time_window_after,
  timing_preference:                  :scheduling_priority,
  trip_purpose:                       :trip_purpose_description,
  trip_funding_source:                { list: [ :trip_funders, '|' ]},
  estimated_trip_distance:            :estimated_distance,
  outcome:                            [ :trip_result_attributes ],
  actual_pickup_time:                 [ :trip_result_attributes, :actual_pick_up_time ],
  actual_drop_off_time:               [ :trip_result_attributes ],
  fare:                               [ :trip_result_attributes ],
  fare_type:                          [ :trip_result_attributes ],
  odometer_start:                     [ :trip_result_attributes ],
  odometer_end:                       [ :trip_result_attributes ],
  driver_name:                        [ :trip_result_attributes, :driver_id ],
  vehicle_name:                       [ :trip_result_attributes, :vehicle_id ]
}

SAMPLE_EXPORT_MAPPING = {
  trip_ticket: {
    __accept_unmapped__:                true,
    id:                                 :clearinghouse_trip_id,
    origin_trip_id:                     :trip_id,
    originator_name:                    :provider,
    origin_customer_id:                 :customer_id,
    customer_middle_name:               { truncate: [:customer_middle_initial, 1] },
    customer_address_id:                { ignore: true },
    customer_address_address_type:      :customer_home_address_type,
    customer_address_phone_number:      { match: [/\(*(\d{3})[-. )]*(\d{3})[-. ]*(\d{4})/, :customer_home_telephone, /\w+[:\-\. ]*\d+(?=\s*$)/, :customer_home_telephone_extension] },
    customer_address_common_name:       :customer_home_common_name,
    customer_address_address_1:         :customer_home_address_1,
    customer_address_address_2:         :customer_home_address_2,
    customer_address_city:              :customer_home_city,
    customer_address_jurisdiction:      :customer_home_county,
    customer_address_state:             :customer_home_state,
    customer_address_zip:               :customer_home_zip,
    customer_address_latitude:          :customer_home_latitude,
    customer_address_longitude:         :customer_home_longitude,
    customer_gender:                    :customer_sex,
    customer_identifiers:               { key_value_merge: [ :customer_internal_id, ','] },
    customer_boarding_time:             :customer_load_time,
    customer_deboarding_time:           :customer_unload_time,
    customer_service_level:             :customer_mobility_requirement,
    customer_mobility_factors:          { list_merge: [ :customer_assistance_needs, '|' ]},
    customer_eligibility_factors:       { list_merge: [ :customer_eligibility, '|' ]},
    pick_up_location_id:                { ignore: true },
    pick_up_location_address_type:      :pickup_address_type,
    pick_up_location_phone_number:      { match: [/\(*(\d{3})[-. )]*(\d{3})[-. ]*(\d{4})/, :pickup_telephone, /\w+[:\-\. ]*\d+(?=\s*$)/, :pickup_telephone_extension] },
    pick_up_location_common_name:       :pickup_common_name,
    pick_up_location_address_1:         :pickup_address_1,
    pick_up_location_address_2:         :pickup_address_2,
    pick_up_location_city:              :pickup_city,
    pick_up_location_jurisdiction:      :pickup_county,
    pick_up_location_state:             :pickup_state,
    pick_up_location_zip:               :pickup_zip,
    pick_up_location_latitude:          :pickup_latitude,
    pick_up_location_longitude:         :pickup_longitude,
    drop_off_location_id:               { ignore: true },
    drop_off_location_address_type:     :drop_off_address_type,
    drop_off_location_phone_number:     { match: [/\(*(\d{3})[-. )]*(\d{3})[-. ]*(\d{4})/, :drop_off_telephone, /\w+[:\-\. ]*\d+(?=\s*$)/, :drop_off_telephone_extension] },
    drop_off_location_common_name:      :drop_off_common_name,
    drop_off_location_address_1:        :drop_off_address_1,
    drop_off_location_address_2:        :drop_off_address_2,
    drop_off_location_city:             :drop_off_city,
    drop_off_location_jurisdiction:     :drop_off_county,
    drop_off_location_state:            :drop_off_state,
    drop_off_location_zip:              :drop_off_zip,
    drop_off_location_latitude:         :drop_off_latitude,
    drop_off_location_longitude:        :drop_off_longitude,
    requested_pickup_time:              { match: [/\d{4}[\/-]\d{1,2}[\/-]\d{1,2}/, :requested_pickup_date, /.*/, :requested_pickup_time] },
    requested_drop_off_time:            { match: [/\d{4}[\/-]\d{1,2}[\/-]\d{1,2}/, :requested_drop_off_date, /.*/, :requested_drop_off_time] },
    time_window_before:                 :early_window,
    time_window_after:                  :late_window,
    scheduling_priority:                :timing_preference,
    trip_purpose_description:           :trip_purpose,
    trip_funders:                       { list_merge: [ :trip_funding_source, '|' ]},
    estimated_distance:                 :estimated_trip_distance,
    customer_service_animals:           { list_merge: [ :customer_service_animals, '|' ]},
    additional_data:                    { key_value_merge: [ :additional_data, ',' ]}
  },
  trip_result: {
    __accept_unmapped__:                true,
    trip_ticket_id:                     :clearinghouse_trip_id,
    origin_trip_id:                     :trip_id,
    actual_pick_up_time:                :actual_pickup_time,
    driver_id:                          :driver_name,
    vehicle_id:                         :vehicle_name
  },
  trip_claim: {
    __accept_unmapped__:                true,
    trip_ticket_id:                     :clearinghouse_trip_id,
    origin_trip_id:                     :trip_id,
    notes:                              :claim_notes,
    claimant_name:                      :claiming_provider
  },
  trip_comment: {
    __accept_unmapped__:                true,
    trip_ticket_id:                     :clearinghouse_trip_id,
    origin_trip_id:                     :trip_id
  }
}

File.open('processors/advanced_processors/sample_data/sample_import_mapping_r.yml', 'w') do |f|
  f.write SAMPLE_IMPORT_MAPPING.to_yaml
end

File.open('processors/advanced_processors/sample_data/sample_export_mapping_r.yml', 'w') do |f|
  f.write SAMPLE_EXPORT_MAPPING.to_yaml
end
