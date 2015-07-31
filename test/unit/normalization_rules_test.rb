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
require './processors/advanced_processors/normalization_rules'

include Processors::AdvancedProcessors

describe Processors::AdvancedProcessors::NormalizationRules do

  it 'accepts rules in initializer' do
    rules = { abc: :xyz }
    NormalizationRules.new(rules).rules == rules
  end

  it 'can load rules from a file' do
    NormalizationRules.new('processors/advanced_processors/sample_data/sample_normalization_rules.yml').rules.wont_be_empty
  end

  it 'saves inputs that have no rules by default' do
    NormalizationRules.new.normalize_inputs(abc: 123)[:abc].must_equal 123
  end

  it 'raises an exception if rule is invalid' do
    rules = { abc: 'invalid' }
    ->{ NormalizationRules.new(rules).normalize_inputs(abc: 'test') }.must_raise(RuntimeError)
  end

  it 'accepts rules as hashes' do
    rules = { abc: {
      normalizations: { 'normal' => ['test'] },
      output_attribute: :def,
      unmatched_action: :accept
    }}
    normalization_rules = NormalizationRules.new(rules)
    normalization_rules.expects(:process_rule).with(:abc, 'test', { 'normal' => ['test'] }, :def, :accept).once
    normalization_rules.normalize_inputs(abc: 'test')
  end

  it 'accepts rules as arrays' do
    rules = { abc: [{ 'normal' => ['test'] }, :def, :accept] }
    normalization_rules = NormalizationRules.new(rules)
    normalization_rules.expects(:process_rule).with(:abc, 'test', { 'normal' => ['test'] }, :def, :accept).once
    normalization_rules.normalize_inputs(abc: 'test')
  end

  it 'supports optional unmatched_action' do
    rules = { abc: [{ 'normal' => ['test'] }, :def] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'test').must_equal({ 'def' => 'normal'})
  end

  it 'supports optional output_attribute and unmatched_action' do
    rules = { abc: [{ 'normal' => ['test'] }] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'test').must_equal({ 'abc' => 'normal'})
  end

  it 'requires output_attribute if unmatched_action is provided' do
    rules = { abc: [{}, :ignore] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'test').must_equal({ 'ignore' => 'test' })
  end

  it 'accepts rules consisting of multiple sub-rules' do
    # an empty set of normalizations {} outputs the input unchanged by default
    # this test just uses the second param -- the output attribute name -- to see which set of sub-rules is used
    rules = { subset1: { my_attr: [{}, :output1] }, subset2: { my_attr: [{}, :output2] }}
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 123 }, :subset2)[:output2].must_equal 123
  end

  it 'copies inputs directly to outputs if sub-rules do not exist' do
    rules = { subset1: { my_attr: [{}, :output1] }, subset2: { my_attr: [{}, :output2] }}
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 123 }, :invalid).must_equal({ 'my_attr' => 123 })
  end

  it 'outputs value unchanged if it exactly matches a normal value' do
    rules = { my_attr: [{ 'FOO' => ['random', 'stuff'] }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'FOO' }).must_equal({ 'my_attr' => 'FOO' })
  end

  it 'performs a case-sensitive match against normal values' do
    rules = { my_attr: [{ 'FOO' => ['random', 'stuff'] }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'foo' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'normalizes inputs by matching against an array' do
    rules = { my_attr: [{ 'foo' => ['random', 'stuff'] }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'performs a case-insensitive match against arrays' do
    rules = { my_attr: [{ 'foo' => ['random', 'stuff'] }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'STUFF' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'accepts regular expressions in match arrays' do
    rules = { my_attr: [{ 'foo' => ['random', /ff$/] }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'raises an exception if match array contains invalid entries' do
    rules = { my_attr: [{ 'foo' => [1234] }] }
    ->{ NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }) }.must_raise(RuntimeError)
  end

  it 'normalizes inputs by matching against a string' do
    rules = { my_attr: [{ 'foo' => 'stuff' }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'performs a case-insensitive match against strings' do
    rules = { my_attr: [{ 'foo' => 'stuff' }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'STUFF' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'normalizes inputs by matching against a regular expression' do
    rules = { my_attr: [{ 'foo' => /ff$/ }] }
    NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }).must_equal({ 'my_attr' => 'foo' })
  end

  it 'raises an exception if match values are not an array, string, or regexp' do
    rules = { my_attr: [{ 'foo' => 123 }] }
    ->{ NormalizationRules.new(rules).normalize_inputs({ my_attr: 'stuff' }) }.must_raise(RuntimeError)
  end

  it 'maps input to a different output name if specified' do
    rules = { abc: [{ 'normal' => ['test'] }, :def] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'test').must_equal({ 'def' => 'normal'})
  end

  it 'preserves input attribute name by default' do
    rules = { abc: [{ 'normal' => ['test'] }] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'test').must_equal({ 'abc' => 'normal'})
  end

  it 'outputs unmatched values by default' do
    rules = { abc: [{ 'normal' => ['match'] }, :def] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch').must_equal({ 'def' => 'nomatch'})
  end

  it 'can accept unmatched values' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, :accept] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch').must_equal({ 'def' => 'nomatch'})
  end

  it 'can ignore unmatched values' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, :ignore] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch').must_equal({})
  end

  it 'can append unmatched values to a notes attribute' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:append, :notes]] }
    NormalizationRules.new(rules).normalize_inputs({abc: 'nomatch'}, nil, {'notes' => 'existing value'})
      .must_equal({ 'notes' => 'existing value\nabc: nomatch' })
  end

  it 'does not add a newline when appending unless there are existing values' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:append, :notes]] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch')
      .must_equal({ 'notes' => 'abc: nomatch' })
  end

  it 'can leave placeholder text when appending unmatched values' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:append, :notes, 'See notes']] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch')[:def].must_equal('See notes')
  end

  it 'can replace an attribute with unmatched values' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:replace, :ghi]] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch').must_equal({ 'ghi' => 'nomatch' })
  end

  it 'can output an arbitrary value in an attribute for unmatched value' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:replace, :ghi, 'unmatched']] }
    NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch').must_equal({ 'ghi' => 'unmatched' })
  end

  it 'raises an exception if unmatched action is invalid' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, :invalid] }
    ->{ NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch') }.must_raise(RuntimeError)
  end

  it 'raises an exception if unmatched action array is invalid' do
    rules = { abc: [{ 'normal' => ['match'] }, :def, [:invalid, :invalid]] }
    ->{ NormalizationRules.new(rules).normalize_inputs(abc: 'nomatch') }.must_raise(RuntimeError)
  end

end
