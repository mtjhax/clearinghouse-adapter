# Advanced Import/Export Processors
The advanced import and export processors can import and export data in custom formats with little or no additional programming.
To accomplish this, two different types of data conversions can be specified in configuration files and applied to both
imported and exported data. The two types of conversions are **attribute mappings** and **normalization rules**.

Attribute mapping is intended to rename attributes and apply transformations such as splitting values into multiple fields,
joining attributes, or appending to existing values. Normalization rules match input values to lists of expected values,
replace values with normalized versions, map the output to a different attribute name, and take various actions if there
is no match for a value. There is some minor overlap between these systems. Full details are below.

The attribute mapping and normalization rules configuration files are stored in YAML format. Attribute mappings should have 
one configuration file for importing and another for exporting, as data conversions are not always the same in both directions.
Normalization rules are only used when exporting data. Detailed examples are available in `processors\advanced_processors\sample_data`.
Example configurations used in the Adapter tests are in `sample_import_mapping.yml`, `sample_export_mapping.yml`, and
`sample_normalization_rules.yml`. The files `create_sample_mappings.rb` and `create_sample_normalization_rules.rb` can be used to
regenerate the YAML files and provide an example of how to define mappings in Ruby then convert to YAML.

## General Configuration
To use the advanced processors, update your `adapter_sync.yml` configuration file to look something like the following:
```yaml
import:
  enabled: true
  processor: advanced_processors/advanced_import_processor.rb
  options:
    import_folder: tmp/import
    completed_folder: tmp/import_done
    mapping_file: ./config/my_import_mapping.yml
export:
  enabled: true
  processor: advanced_processors/advanced_export_processor.rb
  options:
    import_folder: tmp/import
    completed_folder: tmp/import_done
    mapping_file: ./config/my_export_mapping.yml
    normalization_rules_file: ./config/my_normalization_rules.yml
```

## Attribute Mapping
The import/export attribute mapping configuration is a Ruby hash (as expressed in YAML) containing the names of input
attributes as keys and the output attribute names and transformations to apply as values.
```ruby
# Example mapping in Ruby format:
{
  # Mapping can consist of a single hash or can consist of four sub-hashes, one for
  # each data type that can be imported and exported: trip_ticket, trip_claim,
  # trip_comment, trip_result. This example shows the latter:
  
  trip_ticket: {
   
    # The special :__accept_unmapped__ key indicates how to handle unmapped attributes:
    #   - true/nil passes all unmapped attributes to output (default behavior)
    #   - a value of false (or anything else) will skip any unmapped attributes
    __accept_unmapped__:  true,
  
    # a value of true maps the input attribute to an output with the same name
    keep_this_name: true,
  
    # a symbol or string maps specified input to an output attribute with a new name
    old_name: :new_name,
  
    # array indicates an output attribute name that should appear inside a nested hash
    # arrays can be used anywhere an output attribute name can be specified
    # e.g. {car_id: [:car, :model]} maps car_id input value to output[:car][:model]
    car_id: [:car, :model],
  
    # an array with one entry uses the input name as the nested output name
    # e.g. {model: [:car]} maps the model input to output[:car][:model]
    model: [:car],
  
    # arrays can be nested to create multiple levels of nested hash in output
    # e.g. {car_color: [:car, [:ext, :color]]} maps to output[:car][:ext][:color]
    car_color: [:car, [:ext, :color]],
  
    # a hash indicates a transformation to perform,
    # e.g. {input_attr: {command: [ parameters ]}}
    # The possible commands are listed in the following section.
    middle_name: { truncate: [:middle_initial, 1] }
    
  },
  trip_claim: {
  },
  trip_comment: {
  },
  trip_result: {
  }
}
```

### Transformation Commands
In all transformation commands, wherever an attribute name can be specified, an array can be used to place the result in a nested hash of the output.

#### TRUNCATE
* `Parameters: [attribute_name, max_length]`
* Limits output to specified length, e.g. the following would map input `{middle_name: 'Robert'}` to `output[:middle_initial] == 'R'`
```
{ middle_name: { truncate: [ :middle_initial, 1] }}
```

#### PREPEND
* `Parameters: [attribute_name, separator]`
* Prepend input onto target field, e.g. if the phone output already contains value `'x137'`, the following with input `{phone_number: '123-456-7890'}` would result in  `output[:phone] == '123-456-7890 x137'`
```
{ phone: { prepend: [:phone, ' '] }}
```

#### APPEND
* `Parameters: [attribute_name, separator]`
* Append input onto target field, e.g. if the phone output already contains value `'123-456-7890'`, the following with input `{ext: 'x137'}` would result in  `output[:phone] == '123-456-7890 x137'`
```
{ phone_ext: { append: [:phone, ' '] }}
```

#### SPLIT
* `Parameters: [separator, attribute_name, attribute_name, ...]`
* Splits a single input into multiple output attributes based on a separator. Given input `colors: 'red, blue'`, the following would result in `output[:first_color] == 'red'` and `output[:second_color] == 'blue'`
* If there are more split values than attribute names, only the first N values will be stored.
* The separator can be a Ruby regular expression for more complex splitting.
```
{ colors: { split: [',', :first_color, :second_color] }}
```

#### AND
* `Parameters: [attribute_name, attribute_name, ...]`
* Copies a single input into multiple output attributes. Given input `color: 'red'`, the following would result in `output[:first_color] == 'red'` and `output[:second_color] == 'red'`
```
{ color: { and: [:first_color, :second_color] }}
```

#### OR
* `Parameters: attribute_name`
* Copies input to the output attribute unless the output attribute already has a value.
```
{
  day_phone: { or: :phone_number },
  evening_pphone: { or: :phone_number }
}
```

#### MATCH
* `Parameters: [regular_expr, attribute, regular_expr, attribute, ...]`
* Compares input value to each regular expression and outputs the match, if any, to the corresponding attribute. With an input of `{attr: 'first_123 second'}` the following would result in `output[:first_word] == 'first_123'` and `output[:first_number] == '123'`
```
{ attr: { match: [ /\w+/, :first_word, /\d+/, :first_number ]}}
```

#### KEY_VALUES
* `Parameters: [attribute, separator, default_key]`
* Parses input into a set of key-value pairs using colon to separate the keys and values and a custom separator. With input `{phone_numbers: 'home:123-555-1212,work:123-555-3434'}` the following would result in `output[:phones][:home] == '123-555-1212'` and `output[:phones][:work] == '123-555-3434'`
* default_key is used when the string cannot be parsed so the output is still a key-value pair with a single entry, e.g. input '123-555-1212' would result in `output[:phones][:primary] == '123-555-1212'`
```
{ phone_numbers: { key_values: [:phones, ',', :primary] }
```

#### KEY_VALUE_MERGE
* `Parameters: [attribute, separator]`
* The reverse of `key_values`, combines a hash of values into a single string. With input `{phone_numbers: {home: '123-555-1212', work: '123-555-3434'}}` the following would result in `output[:phones] == 'home:123-555-1212,work:123-555-3434'`
* Non-hash inputs are saved as normal outputs.
```
{ phone_numbers: { key_value_merge: [:phones, ','] }
```

#### LIST
* `Parameters: [attribute, separator]`
* Parses input into a list based on specified separator. With input `{phone_numbers: '123-555-1212, 123-555-3434'}` the following would result in `output[:phones] == ['123-555-1212', '123-555-3434']`
```
{ phone_numbers: { list: [:phones, ','] }
```

#### LIST_MERGE
* `Parameters: [attribute, separator]`
* Merges a list input into a single string output. With input `{phone_numbers: ['123-555-1212', '123-555-3434']}` the following would result in `output[:phones] == '123-555-1212,123-555-3434'`
```
{ phone_numbers: { list_merge: [:phones, ','] }
```

#### IGNORE
* `Parameters: any`
* Ignore the input field and do not place it in the output.
* Note that `ignore: false` would still ignore the input. The presence of the `ignore` key triggers the action.
```
{ unused_field: { ignore: true }
```

## Normalization Rules
When exporting Adapter records using the Advanced Export Processor,
a custom configuration file can be used to check the values of imported
fields against a list of matches, replace values with normalized
values, output the normalized value with a different attribute
name if desired, and take various actions when there is no match.

Note that these rules are applied after the advanced processor mappings,
so the input attribute names will be the mapped names, not the originals
from the Adapter.
```
# Example rules in Ruby format:
{
  # As with attribute mapping, normalization rules can consist of a single hash
  # or sub-hashes for trip_ticket, trip_claim, trip_comment, trip_result. This
  # example shows the former (no type-specific sub-hashes, which is generally
  # okay when there are no overlapped attribute names being normalized):
  
  # Hash key defines the input attribute name to which these rules will be applied
  # which in this case is 'mobility_needs' 
  mobility_needs: {
    normalizations: {
      'wheelchair' => ['wheel chair', /(electric|power|powered) wheelchair/i],
      'scooter' => ['power scooter', 'mobility scooter']
    },
    output_attribute: :mobility_requirement,
    unmatched_action: [ :append, :notes, 'See notes field' ]
  }
}
```

### Normalizations
The `normalizations` parameter consists of a hash where the keys are normal values (the desired output)
and the hash values are lists to match inputs again (match sets). When an input value
matches a value in the set, it is replaced in the output by the normal value.
Match sets can be simple strings (which are matched without respect to case), regular
expressions, or arrays of both strings and regular expressions.

### Output Attribute
The `output_attribute` parameter is optional and maps the input to a new output attribute name.
This overlaps the capabilities of the import/export mapping system and is provided
as a convenience so it is not necessary to use both systems for simple mapping.

### Unmatched Action

The `unmatched_action` parameter is optional and specifies what to do when an input value is not matched.

#### ACCEPT
`:accept` places the original input value as-is into the output.
This is the default if no action is specified.
    
#### IGNORE    
`:ignore` causes the input to be ignored and omitted from the output.
    
#### APPEND    
`:append` is used to append unrecognized inputs to a notes field. The appended text will include a newline
(if the output attribute already contains data) followed by "original_attr_name: original_value". Append can
also leave a placeholder in the original attribute such as "See notes field". For example:
```ruby
# example output using append:
{
  mobility_requirement: "See notes field",
  notes: "existing note\nmobility_needs: help with stairs"
}
```

To use append, an array is supplied as the unmatched action with the form:
`[:append, <name of attribute to append to>, <placeholder string>]`

Also see the example above.
    
#### REPLACE    
`:replace` replaces the specified attribute with either the original input value or a fixed replacement.
This can be used to move an input to a specified "unrecognized" attribute or to replace the output with
text such as "Other" or "Unknown".

To use replace, an array is supplied as the unmatched action with the form:
`[:replace, <name of attribute to replace>, <optional replacement value>]`

For example:
```ruby
{
  gender: {
    normalizations: {
      'Male' => ['male', 'man'],
      'Female' => ['female', 'woman']
    },
    unmatched_action: [ :replace, :gender, 'Unspecified' ]
  }
}
```
