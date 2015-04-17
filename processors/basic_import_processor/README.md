# Basic Import Processor

This is a working example of an extended ImportProcessor class and
support files. 

To use it as your import processor, simply update the import section
of your `adapter_sync.yml` configuration file to look like this:

```yaml
import:
  enabled: true
  processor: basic_import_processor/basic_import_processor.rb
  options: 
    import_folder: tmp/import
    completed_folder: tmp/import_done
```

As you can see, this processor requires a two configuration options:
`import_folder`, which is a path where the CSV files will be read from,
and `completed_folder`, which is a path to where the processed files
will be moved to. Both are specified relative to the project root.

In this processor, the #process method will pick up CSV files from the
`import_folder` directory, parse the contents, and format the data to
an array of trip_ticket hashes in the format that the API expects. Then
the #finalize method will move each processed file to the
`completed_folder` directory, and to record the names of the files we
processed so that we don't accidentally process them again later.
(Because of this, each new file should have a unique name, such as a
timestamp.)

This import processor may be a good fit for your local system if you
already have the capability to export to CSV, and your data is already
in a format that is compatible with the Clearinghouse API.

## Testing the Included Import Processor

See the `samples` folder in this directory for examples of what your
CSV files should look like to be compatible with this processor.

TODO add sample files and instructions
