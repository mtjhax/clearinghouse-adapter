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

# This utility script generates an example of advanced export processor normalization
# rules in YAML format, since it is easier to write them out in Ruby.

require 'yaml'

SAMPLE_RULES = {
  trip_ticket: {
    customer_sex: {
      normalizations: {
        'M' => ['m', 'male', 'man'],
        'F' => ['f', 'female', 'woman']
      },
      output_attribute: :gender,
      unmatched_action: [ :replace, :gender, 'U' ]
    },
    mobility_needs: {
      normalizations: {
        'wheelchair' => ['wheel chair', /wheel\s*chair/],
        'scooter' => ['mobility scooter', /scooter/]
      },
      output_attribute: :mobility_requirement,
      unmatched_action: [ :append, :notes, 'See notes field' ]
    }
  }
}

File.open('processors/advanced_processors/sample_data/sample_normalization_rules.yml', 'w') do |f|
  f.write SAMPLE_RULES.to_yaml
end
