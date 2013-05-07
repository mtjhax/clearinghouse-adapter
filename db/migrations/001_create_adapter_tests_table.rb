class CreateAdapterTestsTable < ActiveRecord::Migration
  def change
    create_table :adapter_tests do |t|
      t.string :foo
      t.string :bar

      t.timestamps
    end
  end
end
