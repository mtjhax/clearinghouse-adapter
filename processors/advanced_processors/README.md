# Advanced Import/Export Processors

These advanced processors can import and export data to custom formats with limits or no additional programming. To accomplish this, the data conversions are specified in a mapping configuration file.

The mapping configuration file is stored in YAML format. There is one mapping for importing and another for exporting, since data conversions are not always the same in both directions. Detailed examples are available in `processors\advanced_processors\sample_data`. Example mappings used in the Adapter tests are in `sample_import_mapping.yml` and `sample_export_mapping.yml`. The file `sample_mappings.rb` shows how to define mappings in Ruby that are slightly easier to edit manually and then export to YAML files.
### Configuration
To use these as your processors, update your `adapter_sync.yml` configuration file to look something like the following:
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
```
### Mapping Formats
The import mapping is a Ruby hash (as expressed in YAML) containing the names of input attributes as keys and the output attribute names and transformations to apply as values.
```
{
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

### APPEND
* `Parameters: [attribute_name, separator]`
* Append input onto target field, e.g. if the phone output already contains value `'123-456-7890'`, the following with input `{ext: 'x137'}` would result in  `output[:phone] == '123-456-7890 x137'`
```
{ phone_ext: { append: [:phone, ' '] }}
```

### SPLIT
* `Parameters: [separator, attribute_name, attribute_name, ...]`
* Splits a single input into multiple output attributes based on a separator. Given input `colors: 'red, blue'`, the following would result in `output[:first_color] == 'red'` and `output[:second_color] == 'blue'`
* If there are more split values than attribute names, only the first N values will be stored.
* The separator can be a Ruby regular expression for more complex splitting.
```
{ colors: { split: [',', :first_color, :second_color] }}
```

### AND
* `Parameters: [attribute_name, attribute_name, ...]`
* Copies a single input into multiple output attributes. Given input `color: 'red'`, the following would result in `output[:first_color] == 'red'` and `output[:second_color] == 'red'`
```
{ color: { and: [:first_color, :second_color] }}
```

### OR
* `Parameters: attribute_name`
* Copies input to the output attribute unless the output attribute already has a value. ```
{
  day_phone: { or: :phone_number },
  evening_pphone: { or: :phone_number }
}
```

### MATCH
* `Parameters: [regular_expr, attribute, regular_expr, attribute, ...]`
* Compares input value to each regular expression and outputs the match, if any, to the corresponding attribute. With an input of `{attr: 'first_123 second'}` the following would result in `output[:first_word] == 'first_123'` and `output[:first_number] == '123'`
```
{ attr: { match: [ /\w+/, :first_word, /\d+/, :first_number ]}}
```

### KEY_VALUES
* `Parameters: [attribute, separator, default_key]`
* Parses input into a set of key-value pairs using colon to separate the keys and values and a custom separator. With input `{phone_numbers: 'home:123-555-1212,work:123-555-3434'}` the following would result in `output[:phones][:home] == '123-555-1212'` and `output[:phones][:work] == '123-555-3434'`
* default_key is used when the string cannot be parsed so the output is still a key-value pair with a single entry, e.g. input '123-555-1212' would result in `output[:phones][:primary] == '123-555-1212'`
```
{ phone_numbers: { key_values: [:phones, ',', :primary] }
```

### KEY_VALUE_MERGE
* `Parameters: [attribute, separator]`
* The reverse of `key_values`, combines a hash of values into a single string. With input `{phone_numbers: {home: '123-555-1212', work: '123-555-3434'}}` the following would result in `output[:phones] == 'home:123-555-1212,work:123-555-3434'`
* Non-hash inputs are saved as normal outputs.
```
{ phone_numbers: { key_value_merge: [:phones, ','] }
```

### LIST
* `Parameters: [attribute, separator]`
* Parses input into a list based on specified separator. With input `{phone_numbers: '123-555-1212, 123-555-3434'}` the following would result in `output[:phones] == ['123-555-1212', '123-555-3434']`
```
{ phone_numbers: { list: [:phones, ','] }
```

### LIST_MERGE
* `Parameters: [attribute, separator]`
* Merges a list input into a single string output. With input `{phone_numbers: ['123-555-1212', '123-555-3434']}` the following would result in `output[:phones] == '123-555-1212,123-555-3434'`
```
{ phone_numbers: { list_merge: [:phones, ','] }
```

### IGNORE
* `Parameters: any`
* Ignore the input field and do not place it in the output.
* Note that `ignore: false` would still ignore the input. The presence of the `ignore` key triggers the action.
```
{ unused_field: { ignore: true }
```
