class CreateAdapterTables < ActiveRecord::Migration
  def change
    create_table :imported_files do |t|
      t.string :file_name
      t.integer :size
      t.datetime :modified
      t.integer :rows
      t.integer :row_errors
      t.boolean :error
      t.string :error_msg
      t.datetime :created_at
    end

    create_table :trip_tickets do |t|
      t.integer :ch_id                  # matching ID on the Clearinghouse
      t.datetime :ch_updated_at         # to track the latest change we have seen
      t.boolean :is_originated          # true if originated by our provider

      # originator may reuse an origin_trip_id with a new appointment_time, this should be a separate trip on the CH
      # track these two fields so when importing trips we can determine if trips should be created or updated
      t.integer :origin_trip_id
      t.datetime :appointment_time

      t.text :ch_data                   # the entire clearinghouse ticket stored as JSON
      t.timestamps
    end

    # associated objects will be stored as JSON in the TripTicket ch_data attribute
    # there is no need at the moment to store them in their own tables -- we don't need to query them
    # or look them up except via their associated trip. one thing that would change this is if there
    # were large numbers of claims per trip and we stopped nesting those in the API trips.
    #create_table :trip_claims
    #create_table :trip_results
    #create_table :trip_ticket_comments
  end
end
