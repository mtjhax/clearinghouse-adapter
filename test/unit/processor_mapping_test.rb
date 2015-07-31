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

require 'test_helper'
require './processors/advanced_processors/processor_mapping'

include Processors::AdvancedProcessors

describe Processors::AdvancedProcessors::ProcessorMapping do

  it 'accepts mappings in initializer' do
    mappings = { abc: :xyz }
    ProcessorMapping.new(mappings).mappings == mappings
  end

  it 'can load mappings from a file' do
    ProcessorMapping.new('processors/advanced_processors/sample_data/sample_export_mapping.yml').mappings.wont_be_empty
  end

  it 'saves unmapped inputs by default' do
    ProcessorMapping.new.map_inputs(abc: 123)[:abc].must_equal 123
  end

  it 'saves unmapped inputs if __accept_unmapped__ is true' do
    mappings = { __accept_unmapped__: true }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:abc].must_equal 123
  end

  it 'ignores unmapped inputs if __accept_unmapped__ is false' do
    mappings = { __accept_unmapped__: false }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:abc].must_equal nil
  end

  it 'saves mapped inputs to same attribute name if mapping value is true' do
    mappings = { __accept_unmapped__: false, abc: true }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:abc].must_equal 123
  end

  it 'saves mapped inputs to output attribute represented by a symbol' do
    mappings = { abc: :xyz }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:xyz].must_equal 123
  end

  it 'saves mapped inputs to output attribute represented by a string' do
    mappings = { abc: 'xyz' }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:xyz].must_equal 123
  end

  it 'rejects attribute names that are not strings or symbols' do
    mappings = { abc: 86 }
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 123) }.must_raise(RuntimeError)
  end

  it 'rejects zero-length attribute names' do
    mappings = { abc: '' }
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 123) }.must_raise(RuntimeError)
  end

  it 'saves mapped inputs to a nested attribute represented by an array' do
    mappings = { abc: [ :def, :ghi ] }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:def][:ghi].must_equal 123
  end

  it 'saves mapped inputs to a deeply-nested attribute' do
    mappings = { abc: [ :def, [ :ghi, :jkl ]] }
    ProcessorMapping.new(mappings).map_inputs(abc: 123)[:def][:ghi][:jkl].must_equal 123
  end

  it 'rejects nested attribute mappings that do not have one or two entries' do
    mappings = { abc: [ :def, :ghi, :jkl ] }
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 123) }.must_raise(RuntimeError)
  end

  it 'rejects nested attribute mappings where first entry is not a valid attribute name' do
    mappings = { abc: [ 86, :ghi ] }
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 123) }.must_raise(RuntimeError)
  end

  it 'rejects deeply-nested attribute mappings that are not valid' do
    mappings = { abc: [ :def, [ :ghi, 86 ]] }
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 123) }.must_raise(RuntimeError)
  end

  it 'accepts a mapping consisting of multiple sub-mappings' do
    mappings = { abc: { xyz: :first }, def: { xyz: :second }}
    ProcessorMapping.new(mappings).map_inputs({ xyz: 123 }, :def)[:second].must_equal 123
  end

  it 'outputs a hash with indifferent access' do
    mappings = { abc: :xyz }
    ProcessorMapping.new(mappings).map_inputs(abc: 123).tap do |output|
      output.must_be_kind_of(ActiveSupport::HashWithIndifferentAccess)
      output['xyz'].must_equal(123)
      output[:xyz].must_equal(123)
    end
  end

  it 'maps all inputs directly to outputs if sub-mapping does not exist' do
    mappings = { abc: { xyz: :first }, def: { xyz: :second }}
    ProcessorMapping.new(mappings).map_inputs({ xyz: 123 }, :invalid).must_equal({ 'xyz' => 123 })
  end

  it 'transforms mapped inputs using a specification represented by a hash' do
    mappings = { abc: { def: :ghi }}
    ProcessorMapping.any_instance.expects(:process_command).once.with('def', :ghi, :abc, 123, {}).returns({})
    ProcessorMapping.new(mappings).map_inputs(abc: 123)
  end

  it 'processes all transformations if hash contains multiple entries' do
    mappings = { abc: { def: :ghi, jkl: :mno }}
    ProcessorMapping.any_instance.expects(:process_command).twice.returns({})
    ProcessorMapping.new(mappings).map_inputs(abc: 123)
  end

  it 'raises an exception if transformation is invalid' do
    mappings = { abc: { invalid: [:xyz] }}
    ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'test') }.must_raise(RuntimeError)
  end

  it 'resets output hash for each call' do
    mappings = { abc: :def, ghi: :jkl }
    ProcessorMapping.new(mappings).map_inputs(abc: 123).must_equal('def' => 123)
    ProcessorMapping.new(mappings).map_inputs(ghi: 456).tap do |output|
      output.must_equal('jkl' => 456)
      output.keys.wont_include('def')
    end
  end

  describe 'truncate transformation' do
    it 'truncates inputs to specified length' do
      mappings = { abc: { truncate: [:xyz, 2] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'test'})[:xyz].must_equal('te')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { truncate: [[:abc, :def], 2] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'test'})[:abc][:def].must_equal('te')
    end

    it 'validates parameters' do
      mappings = { abc: { truncate: :invalid }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'test') }.must_raise(RuntimeError)
    end
  end

  describe 'prepend transformation' do
    it 'prepends inputs to an existing output attribute' do
      mappings = { abc: { prepend: [:xyz, '_'] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'start'}, nil, {xyz: 'end'})[:xyz].must_equal('start_end')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { prepend: [[:abc, :def], '_'] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'start'}, nil, {abc: { def: 'end' }})[:abc][:def].must_equal('start_end')
    end

    it 'validates parameters' do
      mappings = { abc: { prepend: nil }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'start') }.must_raise(RuntimeError)
    end
  end

  describe 'append transformation' do
    it 'appends inputs to an existing output attribute' do
      mappings = { abc: { append: [:xyz, '_'] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'start'}, nil, {xyz: 'end'})[:xyz].must_equal('end_start')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { append: [[:abc, :def], '_'] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'start'}, nil, {abc: { def: 'end' }})[:abc][:def].must_equal('end_start')
    end

    it 'validates parameters' do
      mappings = { abc: { append: nil }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'start') }.must_raise(RuntimeError)
    end
  end

  describe 'split transformation' do
    it 'splits input to multiple output attributes' do
      mappings = { abc: { split: ['|', :def, :ghi] }}
      output = ProcessorMapping.new(mappings).map_inputs(abc: 'one | two')
      output[:def].must_equal('one')
      output[:ghi].must_equal('two')
    end

    it 'splits using a regexp' do
      mappings = { abc: { split: [/[|:,]/, :def, :ghi] }}
      output = ProcessorMapping.new(mappings).map_inputs(abc: 'one, two')
      output[:def].must_equal('one')
      output[:ghi].must_equal('two')
    end

    it 'splits to only as many output fields as are provided' do
      mappings = { abc: { split: ['|', :def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one | two | three')[:def].must_equal('one')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { split: ['|', [:def, :ghi]] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one | two')[:def][:ghi].must_equal('one')
    end

    it 'validates parameters' do
      mappings = { abc: { split: [nil, :def, :ghi] }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'one | two') }.must_raise(RuntimeError)
    end
  end

  describe 'and transformation' do
    it 'stores input value in multiple output attributes' do
      mappings = { abc: { and: [:def, :ghi] }}
      output = ProcessorMapping.new(mappings).map_inputs(abc: 'test')
      output[:def].must_equal('test')
      output[:ghi].must_equal('test')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { and: [[:def, :ghi], [:jkl]] }}
      output = ProcessorMapping.new(mappings).map_inputs(abc: 'test')
      output[:def][:ghi].must_equal('test')
      output[:jkl][:abc].must_equal('test')
    end

    it 'validates parameters' do
      mappings = { abc: { and: nil }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'test') }.must_raise(RuntimeError)
    end
  end

  describe 'or transformation' do
    it 'stores input value in blank output attribute' do
      mappings = { abc: { or: :def }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test')[:def].must_equal('test')
    end

    it 'does not store input if output attribute already has a value' do
      mappings = { abc: { or: :def }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'test'}, nil, {def: 'previous'})[:def].must_equal('previous')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { or: [:def, :ghi] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test')[:def][:ghi].must_equal('test')
    end

    it 'validates parameters' do
      mappings = { abc: { or: nil }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'test') }.must_raise(RuntimeError)
    end
  end

  describe 'match transformation' do
    it 'extracts first match from input using a regular expression' do
      mappings = { abc: { match: [/\d+/, :xyz] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'test123test'})[:xyz].must_equal('123')
    end

    it 'extracts multiple matches from input' do
      mappings = { abc: { match: [/\d+/, :number, /\w+/, :word] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'start123end'}).tap do |result|
        result[:number].must_equal('123')
        result[:word].must_equal('start123end')
      end
    end

    it 'stores to nested attributes' do
      mappings = { abc: { match: [/\d+/, [:abc, :xyz]] }}
      ProcessorMapping.new(mappings).map_inputs({abc: 'test123test'})[:abc][:xyz].must_equal('123')
    end

    it 'validates parameters' do
      mappings = { abc: { match: [ :invalid ]}}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'test123') }.must_raise(RuntimeError)
    end
  end

  describe 'key_values transformation' do
    it 'parses input string to a hash in output' do
      mappings = { abc: { key_values: [:def, '|'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one:test1 | two:test2')[:def].must_equal('one'=>'test1', 'two'=>'test2')
    end

    it 'uses comma as default separator' do
      mappings = { abc: { key_values: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one:test1, two:test2')[:def].must_equal('one'=>'test1', 'two'=>'test2')
    end

    it 'uses default key parameter for strings that do not contain a key' do
      mappings = { abc: { key_values: [:def, ',', :default_key] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test')[:def].must_equal('default_key'=>'test')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { key_values: [[:def, :ghi]] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one:test1, two:test2')[:def][:ghi].must_equal('one'=>'test1', 'two'=>'test2')
    end

    it 'validates parameters' do
      mappings = { abc: { key_values: [:def, 86] }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'one:test1, two:test2') }.must_raise(RuntimeError)
    end
  end

  describe 'key_value_merge transformation' do
    it 'merges input hash into a single string output' do
      mappings = { abc: { key_value_merge: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: { one:'test1', two:'test2' })[:def].must_equal('one:test1,two:test2')
    end

    it 'accepts a custom separator' do
      mappings = { abc: { key_value_merge: [:def, '|'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: { one:'test1', two:'test2' })[:def].must_equal('one:test1|two:test2')
    end

    it 'outputs non-hash inputs as normal outputs' do
      mappings = { abc: { key_value_merge: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test')[:def].must_equal('test')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { key_value_merge: [[:def, :ghi]] }}
      ProcessorMapping.new(mappings).map_inputs(abc: { one:'test1', two:'test2' })[:def][:ghi].must_equal('one:test1,two:test2')
    end

    it 'validates parameters' do
      mappings = { abc: { key_value_merge: :invalid }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: { one:'test1', two:'test2' }) }.must_raise(RuntimeError)
    end
  end

  describe 'list transformation' do
    it 'parses input string to an array in output' do
      mappings = { abc: { list: [:def, '|'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one | two')[:def].must_equal(%w(one two))
    end

    it 'uses comma as default separator' do
      mappings = { abc: { list: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one, two')[:def].must_equal(%w(one two))
    end

    it 'stores to nested attributes' do
      mappings = { abc: { list: [[:def, :ghi]] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'one, two')[:def][:ghi].must_equal(%w(one two))
    end

    it 'validates parameters' do
      mappings = { abc: { list: [:def, 86] }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: 'one, two') }.must_raise(RuntimeError)
    end
  end

  describe 'list_merge transformation' do
    it 'merges input array into a single string output' do
      mappings = { abc: { list_merge: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: ['test1', 'test2'])[:def].must_equal('test1,test2')
    end

    it 'accepts a custom separator' do
      mappings = { abc: { list_merge: [:def, '|'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: ['test1', 'test2'])[:def].must_equal('test1|test2')
    end

    it 'outputs non-array inputs as normal outputs' do
      mappings = { abc: { list_merge: [:def] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test')[:def].must_equal('test')
    end

    it 'stores to nested attributes' do
      mappings = { abc: { list_merge: [[:def, :ghi]] }}
      ProcessorMapping.new(mappings).map_inputs(abc: ['test1', 'test2'])[:def][:ghi].must_equal('test1,test2')
    end

    it 'validates parameters' do
      mappings = { abc: { list_merge: :invalid }}
      ->{ ProcessorMapping.new(mappings).map_inputs(abc: ['test1', 'test2']) }.must_raise(RuntimeError)
    end
  end

  describe 'ignore transformation' do
    it 'does not store input' do
      mappings = { abc: { ignore: true }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'test').must_equal({})
    end
  end

  describe 'combined transformations' do
    it 'does not repeat separators when combining prepend and append' do
      mappings = { abc: { prepend: [:xyz, '_'] }, def: { append: [:xyz, '_'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'start', def: 'end')[:xyz].must_equal('start_end')
    end

    it 'does not repeat separators when combining append and prepend' do
      mappings = { abc: { append: [:xyz, '_'] }, def: { prepend: [:xyz, '_'] }}
      ProcessorMapping.new(mappings).map_inputs(abc: 'end', def: 'start')[:xyz].must_equal('start_end')
    end
  end

end
