FactoryGirl.define do

  factory :imported_file do
    file_name "import.csv"
    modified Time.now.utc
    size 123
    rows 5

    factory :imported_file_with_error do
      error true
      error_msg "This file is junk"
    end
  end

end