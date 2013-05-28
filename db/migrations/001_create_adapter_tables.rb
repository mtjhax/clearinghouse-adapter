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

    create_table :tracked_tickets do |t|
      t.integer :clearinghouse_id
      t.integer :origin_trip_id
      t.datetime :appointment_time
      t.timestamps
    end
  end
end
