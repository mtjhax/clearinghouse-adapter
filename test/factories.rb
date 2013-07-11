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

  factory :trip_ticket do
    ch_id 1
    ch_updated_at '1 July 2013 12:00:00 UTC'
    is_originated true
    origin_trip_id 111
    appointment_time '1 August 2013 12:00:00 UTC'
  end

end