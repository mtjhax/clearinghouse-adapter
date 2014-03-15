# Basic Export Processor

This is working example of an extended ExportProcessor class. 

To use that as your export processor, simply update the export section
of your `adapter_sync.yml` configuration file to look like this:

```yaml
export:
  enabled: true
  processor: basic_export_processor/basic_export_processor.rb
  options: 
    export_folder: tmp/export
```

This processor requires a single configuration option, `export_folder`,
which is a path (relative to the project root) where the CSV files will
be saved. Anytime the adapter receieves changes from the API it will
dump the results to flat CSV files in this folder. The files will be
named `trip_object.yyyy-mm-dd.hhmmss.csv` where `trip_object` is one of
`trip_claims`, `trip_results`, `trip_ticket_comments`, or
`trip_tickets`, and where `yyyy-mm-dd` is the current date and `hhmmss`
is the time the file was created.

In this processor, the #process method will write out the exported trip
data to CSV files: one each for trip tickets, trip claims, trip
comments and trip results. The data will remain largely unchanged,
though we will flatten out any array or hstore (hash) attributes into
individual columns, and any associated address attributes will be added
as columns on the trip record. See the example files in the `samples`
folder in this directory to get an idea of what the resulting files
will look like.

A use case for this processor may be that you wish to open the
resulting files in Excel to perform further processing or reporting
prior to using a database administration tool to import them into your
transportation system database.

## Testing the Included Export Processor

TODO add sample files and instructions