# Ride Connection Clearinghouse Adapter

# Introduction

The Ride Clearinghouse Adapter is a software system that simplifies back
office integration with the Ride Clearinghouse web site. The software
mirrors your company’s Clearinghouse tickets and can be used to help
automate the process of sending and receiving new data though the
Clearinghouse API.

Note that the terms "import" and "export" are from the point of view of
the Clearinghouse API. This software *imports data from the local 
system* into the API, and *exports data from the API* to the local 
system.

# Installation

## Requirements

### Hardware

-   PC capable of running Windows XP or later.
-   Continuous Internet connection (high-speed Internet recommended).

### Software

-   Windows XP or later (Windows Server preferred).
-   The Adapter software (provided as a `.zip` file).
-   A program capable of opening `.zip` files (WinZip, WinRar, 7-Zip).

### Other

-   Login with Administrator privileges on PC.
-   Ride Clearinghouse *Public API Key* and *Private API Key*. These are
    values that can be provided by someone with a Provider Admin login
    for your company on the Ride Clearinghouse web site and will look
    like a long strings of random numbers and letters (e.g.
    8bfdf4b8c05b69d1f43d01f8bd3da682).
-   The credentials and settings for an SMTP or sendmail account that
    can be used to send error notifications via email.
-   An email address that can receive error notifications.

## Preparation

-   Ensure that PC has appropriate security. Customer data will be
    present within the Adapter directories and they should only be
    accessible by approved personnel.
-   Disable automatic standby, hibernate, and screen savers other than
    screen power-saving on the PC.

## Files

Extract the Adapter software into a directory, preserving the .zip
file’s subdirectories (`c:\adapter` is recommended and will be used in
subsequent examples).

Add `c:\adapter\ruby\bin` to your Windows PATH:

-   Open Start -\> Control Panel -\> System (may differ on other
    versions of Windows, can also right-click on My Computer and select
    Properties).
-   Click on the Advanced tab.
-   Click on Environment Variables.
-   In the System list, modify PATH to start with `c:\adapter\ruby\bin`
    *(must be in System, not User, so the Windows Service that runs the
    Adapter can see the PATH change).*
-   Reboot the computer so the PATH changes take effect.
-   If you have the Ruby programming language already installed on the
    computer, it will no longer be accessible without restoring the
    previous PATH temporarily.

Open a new Windows Command Prompt.

Verify that the PATH is correct by typing `gem -v` at the command 
prompt. You should see a number similar to `1.8.24`. If you see a 
command not found error, then the PATH is incorrect.

Make sure the PC has an active Internet connection. The remaining steps
will download and install additional required files.

Change your current directory to the Adapter program directory:

```
cd c:\adapter
```

-   Type the following at the command prompt:

```
gem install bundler --no-rdoc --no-ri
```

Response should be similar to:

```
Fetching: bundler-1.3.5.gem (100%)\
 Successfully installed bundler-1.3.5\
 1 gem installed
```

-   Next, type the following:

```
bundle install
```

There should be a large amount of information displayed on the screen,
ending with something similar to:

```
Your bundle is complete!
```

## Configuration

All of the configuration scripts are located in the `config` folder. If
this is your first time installing the service, simply copy all of the
`.example` files to begin with. For instance, open the
`c:\adapter\config\api.yml.example` file and resave it as 
`c:\adapter\config\api.yml`.

### adapter_sync.yml

Locate and edit the file `c:\adapter\config\adapter_sync.yml` with a 
text editor (e.g. Wordpad.exe or Notepad.exe)

-   This file enables importing and exporting of trip ticket 
    information. 
-   If you enable either option, you will also need to
    specify the path to a processor script. See the Processor section
    below for more information.
-   Some processors require additional options to be configured, which
    can also be specified here. See below for more information.

### api.yml

Locate and edit the file `c:\adapter\config\api.yml`

-   Find each instance of `api_key:` and replace the value that follows
    on the same line with your actual *Public API Key*.
-   Find each instance of `api_private_key:` and replace the value that
    follows on the same line with your actual *Private API Key*.
-   Save and close the file.

### database.yml

The default configuration for this file should be sufficient for most
instalations.

### mail.yml

Locate and edit the file `c:\adapter\config\mail.yml`

-   This file enables the Adapter to send an email notification when
    there are errors that should be dealt with by an administrator.
    Detailed instructions on configuration settings are available at
    http://guides.rubyonrails.org/action_mailer_basics.html#action-mailer-configuration 
-   Typically, the following settings will need to be modified:

```yaml
connection:\
   address: [an outbound email server, e.g. smtp.my_isp.net]\
   domain: [your email domain, e.g. mycompany.com]\
   user_name: [valid email sender login name]\
   password: [valid email sender password]\
 message:\
   to: [email of person who will receive notifications]\
   from: [email used as From: address]
```

-   It is recommended that you use TLS and/or SSL so emails are sent
    securely. No customer data is included in email notifications at
    this time, but it is recommended just in case. Security will be
    enabled automatically (via setting `enable_starttls_auto: true`) if
    your email provider supports the STARTTLS feature. You can also
    force TLS or SSL security, e.g. to force SSL, set `ssl: true, port:
    465`, and `openssl_verify_mode: peer` (to force SSL to validate the
    server certificate).

## Service Installation

-   The Adapter runs in the background as a Windows Service. To install
    the service, type the following at the Windows command prompt:

```
c:\adapter\bin\install_adapter_service
```

-   If uninstalling the Adapter, before deleting any files use:

```
cd c:\adapter
c:\adapter\bin\remove_adapter_service
```

## Import Test

TODO move to Import Processor section

The file `c:\adapter\test\csv\sample_tickets.csv` contains four sample
tickets that can be imported to make sure the Adapter is working
properly. To test, simply copy this file into `c:\adapter\tmp\import`.
Within a minute, the Adapter should attempt to import the file and log
its results in `c:\adapter\tmp\import_done\import.log` (this
directory may be changed – configuration detailed below). If there is an
error, an email notification should be sent assuming email notifications
are properly configured.

The import test will cause four fictitious trips to be posted on the
Clearinghouse – these can be checked by logging into the web site. There
should be one each for customers:

-   Gloria Stevens
-   Philip Carroll
-   Teresa Jones
-   Antonio Vasquez

These should be rescinded (cancelled) as soon as possible so claimants
do not think they are real trips. To rescind a trip, click the customer
name in the right-hand panel to see the full trip details, then find the 
Rescind action in the left panel.

# Operations

## Starting / Stopping the Windows Service

-   The Adapter is started by simply starting its Windows Service, which
    is called *Ride Clearinghouse Adapter*. This can be done through
    Control Panel -\> Administrative Tools -\> Services.
-   To start and stop the Adapter from the command prompt, use the
    standard Windows service control program:

```
sc start ride_clearinghouse_adapter\
sc stop ride_clearinghouse_adapter
```

-   If the Adapter is running, you will see log files appear in
    `c:\adapter\log`. The dates and times in the logs should be updated
    every few minutes and indicate that the polling process is
    successfully being initiated.
-   The file adapter_monitor.log should contain something like the
    following (where exit 0 at the end indicates that a polling session
    completed with no errors):

```
 # Logfile created on 2013-07-02 16:54:09 -0400 by logger.rb/31641
```
```
I, [2013-07-02T16:54:09.031250 #2568]  INFO -- : Starting sync worker
with command ["C:/Adapter/ruby/bin/ruby" "C:/Adapter/ruby/bin/rake"
adapter_sync] in directory [C:/Adapter]...
```
```
I, [2013-07-02T16:54:13.203125 #2568]  INFO -- : Worker process
complete, pid 2552 status pid 2552 **exit 0**
```

-   The file `adapter\monitor_errors.log` should generally be empty, but
    will sometimes contain routine information that is not captured in
    the other logs.
-   The file `adapter_sync.log` will contain detailed debugging
    information on the polling session including new data downloaded
    from the Clearinghouse and any files that were imported and uploaded
    to the Clearinghouse.

## Clearinghouse Synchronization

Synchronization with the clearing house is done automatically by polling
the API at regular intervals. The polling process is three steps:

1.  Poll the Clearinghouse API for updates since the last time we polled
2.  Run any updates through the export processor
3.  Run the import proceessor and send anything it reports back up to
    the API

TODO Add a separate document will contain the complete specifications
for allowed and required fields, formats, and exported files.

### General Interactions

#### Receiving New and Changed Trip Tickets

When the Adapter polls the first time, it creates a local copy of all
Clearinghouse trip tickets originated by your company. This allows the
Adapter to determine which imported trips are new trips vs. updates.
Subsequent polling will update the local copy of trips as necessary.
The local copy is stored in a simplified table in a local Sqlite
database. You can access this database from you processing scripts if
you need to, but it is important that your scripts not alter the data
in any way, i.e. your access should be limited to read-only.

#### Receiving  Claims, Comments, and Results

The same way new and modified trip tickets are received from the API,
new and modified trip ticket claims, comments, and results are also
received. They are passed into the export processor as nested hashes of
each trip attribute hash.

#### Receiving Claimed Trip Tickets

When your company submits a claim on a trip ticket on the Clearinghouse
web site, your Adapter will then download and export a copy of that trip
ticket, its associated claims and comments, and updates. This allows you
to track any changes to the trip you have claimed, for example if it was
cancelled or the appointment time was changed. This also allows you to
receive notification when your claim is approved or declined.

#### Sending Changes to a Shared Trip Ticket

When you have local changes to a shared ticket that you want to update
in the clearing house, ensure that your import processor includes the
fields `origin_trip_id` and `appointment_time` (both are required) for
matching, so the original trip is updated and a new trip is not
created. It is best to send all of the fields for a trip ticket, even
those that have not changed. If you want to explicitly remove the value
of an old field, simply specify an empty value.

#### Sending Trip Results to the Clearinghouse

When a trip you have successfully claimed has been fulfilled or
otherwise completed, one would typically enter the trip result on the
Clearinghouse. Trip results can also be sent to the Clearinghouse the 
import process by including them as nested attributes on any claimed 
trip that you post to the API.

### Import and Export Processors

Each installation requires an import and an export processor class to
be defined to act as middle-ware between the software and the adapter.
Because every provider's transportation software system is different,
the software is configured such that you can provide your own custom
processors that interact with your own system as you see fit.

You **must** have a processor configured to use the import and/or export
functionality. If you enable one of these features but don't  supply a 
path to a working processor, the synchronization process will fail with 
an error message each time it is run. A set of sample processors are 
included in the `processors` folder of the adapter project. You can use 
these as templates to create your own, or use them as working processors 
if your import and export needs are basic.

Please note that writing your own processor requires a moderate 
understanding of the Ruby programming language and Object Oriented
programing methodologies. If you need help implimenting your own
processor solution, please contact Ride Connection for more information.

#### Export Processor

The export processor is responsible for taking trip ticket data coming 
from the Clearinghouse API and ensuring that the information is 
integrated into your local transportation system.

##### Using the included export processor

To use the included export processors, simply update the export section
of your `adapter_sync.yml` configuration file to look like this:

```yaml
export:
  enabled: true
  processor: processors/basic_export_processor.rb
  options: 
    export_folder: tmp/export
```

Anytime the adapter receieves changes from the API it will dump the 
results to flat CSV files in the `c:\adapter\tmp\export` folder. 

An example use case for this scenario may be that you can open these 
export files in Excel to perform further processing or reporting, or
use a database administration tool to import them into your 
transportation system database.

###### Testing the Included Export Processor

TODO add sample files and instructions

##### Writing your own export processor

If the basic functionality described above doesn't work for your system
you can roll your own export processor. Export processors can do
anything that Ruby can do - you can add gems, talk to a database, write
files, peform calculations, etc. Some examples of what a custom export
processor might do would be to massage clearinghouse data into a format
that is better suited for the local transportation software, or
interact directly with a database as opposed to writing to a flat file.

To start writing your own, simply create a new file in the processors 
directory with a `.rb` extension. Your class must be named 
`ExportProcessor` and it should inherit from the 
`Processor::Export::Base` class, so add the following to your new file:

```ruby
class ExportProcessor < Processor::Export::Base
end
```

The Processor::Export::Base class that your ExportProcessor inherits 
from includes an initializer, so you generally won't need to write your 
own `initialize` method. In the rare case that you do, be sure to call
`super` at the begining of your own `initialize` method so that the
inherited initializer is run first.

All ExportProcessor instances must impliment a public `process` method.
You can add as many supporting methods or modules as necessary, but the
only one that will be called by the adapter is the `process` method.

###### The `process` Method

This method must always accept one argument: an array of trip
attribute hashes (including nested association attributes). It should
not return any value. What the method does with the data is dependent
on the local system and can be customized as neecessary. A basic 
definition would look like this:

```ruby
class ExportProcessor < Processor::Export::Base
  def process( parsed_json_array )
    parsed_json_array.each do |trip_attribute_hash|
      # do your processing here
    end
    
    # Add code to complete your export process by writing to a file,
    # database, etc.
  end
end
```

Each trip ticket hash in the incoming array will include 4 nested
objects:

-   `:trip_claims` will be an array of trip claim attributes if the 
    trip has any claims on it.
-   `:trip_ticket_comments` will be an array of trip comment attributes
    if the trip has any comments.
-   `:trip_result` will be a hash of result attributes if the trip has
    a result associated with it.
    
Each of these nested objects, and the trip ticket attribute hash
itself, will include a special boolean attribute named `:new_record`.
This will be `true` if the adapter does not recognize the trip or
nested objects from previous exports. You can, for example, use this
special attribute in your custom export script to determine wither you
need to insert or update a record in your local system.

When you are done creating your export processor, update the 
`adapter_sync.yml` configuration file to point to your new script.

###### Export Processor options

The inherited initializer is configured to accept any options that your
custom processor may need and make them available in the `@options`
instance variable. For instance, in the supplied processor we needed to
specify a folder where the exported files would be saved. Any options
you'd like to make available to an instance of the ExportProcessor can
be specified in the config/adapter_sync.yml file under the
export[:options] area. You can specify as many options as you need for
your specific implementation. For example:

```yaml
export:
  enabled: true
  processor: processors/your_export_processor.rb
  options: 
    export_folder: tmp/export
    some_other_option: some_value
```

Then anywhere in your export class you could reference 
`@options[:some_other_option]` to get `some_value`.

###### Logging and Error Reporting

The inherited initializer also instantiates the `@logger` and `@errors`
instance variables. The `@logger` variable will be a standard Ruby
logger object that you can write log messages to for debugging or
informational purposes. The `@errors` variable is an array (initially
empty), which you can assign any error messages that you would like to
be sent to system admins after the `process` method has been called as
part of the AdapterSync process.

#### Import Processor

When a provider cannot fulfill a trip and wish to share it in the Ride
Clearinghouse for other providers to claim, they would typically enter
the trip ticket to be shared on the Clearinghouse web site. Using the
Adapter, a trip ticket could be posted to the Clearinghouse directly.

The import processor is responsible for formatting this trip ticket data
from the local system and preparing it for upload to the Clearinghouse
API.

##### Using the included import processor

To use the included import processors, simply update the import section
of your `adapter_sync.yml` configuration file to look like this:

```yaml
import:
  enabled: true
  processor: processors/basic_import_processor.rb
  options: 
    import_folder: tmp/import
    completed_folder: tmp/import_done
```

This will cause the import processor to look for CSV (comma-separated
values, see http://en.wikipedia.org/wiki/Comma-separated_values) files
in `c:\adapter\tmp\export` that end with a `.txt` or `.csv` extension.
It expects the files to be formatted in the same way that the basic
export processor saves them. (You can review the sample CSV file
included in the
`c:\adapter\processors\basic_import_processor\sample_tickets.csv` to
get an idea of what the format should be.) When it is done processing a 
file, it will attempt to move it to the `completed_folder` location. It
also keeps track of what files have been imported previously so as not
to accidentally re-import the same file twice. (Because of this, each 
new file should have a unique name, such as a timestamp.)

This basic processor may be a good fit for your local system if you
already have the capability to export to CSV, and your data is already
in a format that is compatible with the Clearinghouse API.

###### Testing the Included Import Processor

TODO add sample files and instructions

##### Writing your own import processor

If the basic functionality described above doesn't work for your system
you can roll your own import processor. Like the export processors,
import processors can do anything that Ruby can do. Some examples of
what a custom ImportProcessor might do would be to massage data from
the local transportation system into a format that is better suited for
the clearinghouse API, or to pick up data directly from a database as
opposed to reading from a file.

To start writing your own, simply create a new file in the processors 
directory with a `.rb` extension. Your class must be named 
`ImportProcessor` and it should inherit from the 
`Processor::Import::Base` class, so add the following to your new file:

```ruby
class ImportProcessor < Processor::Import::Base
end
```

The Processor::Import::Base class that your ImportProcessor inherits 
from includes an initializer, so you generally won't need to write your 
own `initialize` method. In the rare case that you do, be sure to call
`super` at the begining of your own `initialize` method so that the
inherited initializer is run first.

All ImportProcessor instances must impliment **two** public methods:
`process` and `finalize`, You can add as many supporting methods or
modules as necessary, but only those two methods will be called by the
adapter.

###### The `process` Method

The `public` method accepts no arguments. It must return an array of
hashes, each one representing all of the attributes for a trip ticket
that the CH API would expect, and in the proper format. Where the data
originates from and what sort of transformations you perform on it is
dependent on the local system and can be customized as neecessary. A 
basic definition would look like this:

```ruby
class ExportProcessor < Processor::Export::Base
  def process
    trip_hashes = []
    
    # Pick up your data from some external source
    
    # Process the data, adding each on to the trip_hashes array
    
    # Complete the process by returning the trip_hashes array
    return trip_hashes
  end
end
```

###### The `finalize` Method

The `finalize` method accepts three arguments: `imported_rows`,
`skipped_rows`, and `unposted_rows`. Each of these is an array
containing zero or more trip hashes. (The hashes will be in the same
format as those reterned by the `process` method) The method should not
return any value. While it is required that you define this method in
your ImportProcessor class, it is not required that it actually do any
thing. It is provided as an optional end point for performing cleanup,
reporting, maintenance, etc. A bare-minimum, no-op implementation would
look like this:

```ruby
class ExportProcessor < Processor::Export::Base
  def process
    # ...
  end
  
  def finalize (imported_rows, skipped_rows, unposted_rows)
    # no-op
  end
end
```

See the included `basic_import_processor.rb` script for an example of
what a working finalize script may do.

When you are done creating your import processor, update the 
`adapter_sync.yml` configuration file to point to your new script.

###### Import Processor options

The inherited initializer is configured to accept any options that your
custom processor may need and make them available in the `@options`
instance variable. For instance, in the supplied processor we needed to
specify folders where the imported files would be read from and then
moved to. Any options you'd like to make available to an instance of
the ImportProcessor can be specified in the config/adapter_sync.yml
file under the import[:options] area. You can specify as many options
as you need for your specific implementation. For example:

```yaml
import:
  enabled: true
  processor: processors/your_import_processor.rb
  options: 
    import_folder: tmp/import
    some_other_option: some_value
```

Then anywhere in your import class you could reference 
`@options[:some_other_option]` to get `some_value`.

###### Logging and Error Reporting

The inherited initializer also instantiates the `@logger` and `@errors`
instance variables. The `@logger` variable will be a standard Ruby
logger object that you can write log messages to for debugging or
informational purposes. The `@errors` variable is an array (initially
empty), which you can assign any error messages that you would like to
be sent to system admins after both the `process` and `finalize`
methods have been called as part of the AdapterSync process.

## Notifications

### Worker Process Failure

If the Adapter worker process experiences an unhandled error while
“polling” (importing new data and synchronizing with the Ride
Clearinghouse service), it will cause the service to send out an email
notification containing the number of errors since the last successful
poll, and the number of errors since the last notification.
Notifications are spaced a minimum of five minutes apart to prevent
excessive numbers of emails.

### Service Outage

When the Adapter worker process has failed ten times consecutively, the
Adapter will send out a service outage notification and stop sending
notifications until a successful poll occurs. This prevents
notifications from being sent out continuously if no one is available to
correct the error for some time.

### Polling Errors

Any errors

-   When Clearinghouse service errors are encountered, a notification
    will be sent containing a message similar to: “Encountered {\#}
    errors while syncing with the Ride Clearinghouse” followed by the
    error description. Details on these errors will be located in
    c:\adapter\log\adapter_sync.log.
-   Any errors that the import and export processors add to their 
    `@errors` array will be sent as notifications after their processing
    work has completed.

## Logging

### Adapter Monitor Log

Located in: `c:\adapter\log\adapter_monitor.log`

Details the activities of the Windows Service, the polling process it
invokes periodically, and notifications that were sent.

#### Log Messages

-   Starting sync worker with command [program file] in directory
    [adapter directory]...\
     Indicates that the polling process was started to handle imports
    and exports.
-   Worker process complete, pid \#[process ID] status [\#]\
     Indicates that the polling process completed. If status is anything
    but 0, the polling process exited with an unhandled error. Check the
    Adapter Monitor Errors Log for details.
-   Adapter worker process exited with status [\#]\
     Same as above – the polling process exited with an error.
-   Unhandled exception in AdapterMonitor: [error]\
     An unhandled program error was detected in the Adapter Monitor (the
    Windows Service that keeps the Adapter running in the background). 
-   Sending failure notification\
     An error notification email is being sent.
-   Notification complete\
     The error notification email was successfully sent.
-   Notification failed, check logs
-   Service outage detected, no additional notifications will be sent\
     To avoid continuously sending error notifications over long periods
    of time, notifications are only sent once every 5 minutes. A
    “service outage” is declared if 10 consecutive polls fail with
    errors. No additional emails will be sent until service is restored.
-   Sending service restored notification\
     A service outage ended and an email notification was sent
    indicating this.

### Adapter Monitor Errors Log

Located in: `c:\adapter\log\adapter_monitor_errors.log`

Contains any unhandled output or errors generated by the Adapter polling
or email notification processes and is useful when resolving problems
with an Adapter installation.

### Adapter Sync Log

Located in: `c:\adapter\log\adapter_sync.log`

Contains detailed activity and debugging information for the Adapter’s
main worker process. Any messages that your Import or Export processor 
scripts send to their `@logger` objects will also be included here.

#### Log Messages

The Adapter Sync Log contains detailed debugging information including
database operations. The complete list of logged messages cannot be
covered here. Typical log messages useful in identifying normal
operation are as follows:

-   Retrieved [\#] updated trips from API\
     The Adapter has found trip tickets on the Clearinghouse server that
    are new, updated, or have new comments, claims, or results added.
-   Error notification failed, could not send email: [email contents]\
     There is a problem with sending emails from the Adapter. Check
    email notification configuration in `c:\adapter\config\mail.yml`.

#### Normal Log Messages

-   POST trip ticket with API, result [server API response]\
     The import process created a new trip on the Clearinghouse server.
-   PUT trip ticket with API, result [server API response]\
     The import process updated an existing trip on the Clearinghouse
    server.

#### Common Error Messages

-   API result does not contain an ID\
     This indicates an error when exchanging data with the Clearinghouse
    – the response from the server was missing a key field.
-   API error on POST: [error message]\
     Indicates an error from the Clearinghouse while attempting to
    create a new trip ticket. Generally this results from improper or
    missing data fields.
-   API error on PUT: [error message]\
     Indicates an error from the Clearinghouse while attempting to
    update an existing trip. Generally this results from improper or
    missing data fields.

# Removal

Uninstalling the Adapter is generally the process of following the 
installation steps in reverse: 

-   Stop the Adapter’s Windows Service:

```
sc stop ride_clearinghouse_adapter
```

-   Remove the Windows Service:

```
c:\adapter\bin\remove_adapter_service
```

-   Remove `c:\adapter\ruby\bin` from your PATH.
-   Delete all files in `c:\adapter` and delete the directory.

# Development Notes

## Command Line Operation

If you wish to use or test the Adapter from the command line:

-   Make sure your config scripts exist and are correct.
-   From the command line, switch to the main adapter directory, then 
    start up an Interactive Ruby (irb) session:

```
$ irb -Ilib
```

-   Include the adapter_sync library and create an instance:

```
require 'adapter_sync'
adapter_sync = AdapterSync.new
```

-   From here you can call any method of the AdapterSync class, for 
    example:

```
adapter_sync.poll
```

-   If you wish to use debugging, you will have to add 
    `require 'debugger'` in lib/adapter_sync.rb before adding any 
    `debugger` statements

## Testing

```
bundle exec rake test
```

Tests that require communication with an API endpoint should save and
reuse VCR sessions so that a running API is not a requirement for
running subsequent tests. 

If you are developing new tests that need to talk to an instance of the
API, you can clone the project from 
https://github.com/rideconnection/clearinghouse and run the server 
locally. You will need to ensure that a Provider exists and specify that
provider's public and private keys in the config scripts for the 
adapter.
