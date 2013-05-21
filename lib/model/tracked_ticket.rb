class TrackedTicket < ActiveRecord::Base
  # Attributes:
  #t.integer :origin_trip_id
  #t.integer :clearinghouse_id
  #t.timestamps

  # Ideas for attributes to support update tracking:
  # boolean indicating if ticket was imported or pulled directly from database
  # list of fields that were being tracked when ticket last synced
  # hash / checksum of the tracked fields
  # date origin row was last touched, if available

  # Other Clearinghouse trip ticket columns we may want to track:
  #
  #  t.integer       "origin_provider_id"
  #  t.string        "origin_customer_id"
  #  t.integer       "claimant_provider_id"
  #  t.integer       "claimant_trip_id"
  #
  #  t.integer       "customer_address_id"
  #  t.integer       "pick_up_location_id"
  #  t.integer       "drop_off_location_id"
  #
  #  t.hstore        "customer_identifiers"
  #
  #  t.boolean       "customer_information_withheld"
  #  t.date          "customer_dob"
  #  t.string        "customer_primary_phone"
  #  t.string        "customer_emergency_phone"
  #  t.text          "customer_impairment_description"
  #  t.integer       "customer_boarding_time"
  #  t.integer       "customer_deboarding_time"
  #  t.integer       "customer_seats_required"
  #  t.text          "customer_notes"
  #  t.string        "scheduling_priority"
  #  t.integer       "allowed_time_variance"
  #  t.integer       "num_attendants"
  #  t.integer       "num_guests"
  #  t.string        "trip_purpose_code"
  #  t.string        "trip_purpose_description"
  #  t.text          "trip_notes"
  #  t.string        "customer_primary_language"
  #  t.string        "customer_first_name"
  #  t.string        "customer_last_name"
  #  t.string        "customer_middle_name"
  #  t.time          "requested_pickup_time"
  #  t.time          "requested_drop_off_time"
  #  t.string_array  "customer_mobility_impairments",        :limit => 255
  #  t.string        "customer_ethnicity"
  #  t.string_array  "customer_eligibility_factors",         :limit => 255
  #  t.string_array  "customer_assistive_devices",           :limit => 255
  #  t.string_array  "customer_service_animals",             :limit => 255
  #  t.string_array  "guest_or_attendant_service_animals",   :limit => 255
  #  t.string_array  "guest_or_attendant_assistive_devices", :limit => 255
  #  t.string_array  "trip_funders",                         :limit => 255
  #  t.string        "customer_race"
  #  t.time          "earliest_pick_up_time"
  #  t.datetime      "appointment_time"
end
