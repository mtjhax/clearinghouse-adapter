# Ride Connection Clearinghouse Adapter

# Introduction

The Ride Clearinghouse Adapter is a software system that simplifies back
office integration with the Ride Clearinghouse web site. The software
mirrors your company’s Clearinghouse tickets and can be used to help
automate the process of sending and receiving new data though the
Clearinghouse API.

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

Locate and edit the file `c:\adapter\config\api.yml` with a text editor
(e.g. Wordpad.exe or Notepad.exe)

-   Find each instance of `api_key:` and replace the value that follows
    on the same line with your actual *Public API Key*.
-   Find each instance of `api_private_key:` and replace the value that
    follows on the same line with your actual *Private API Key*.
-   Save and close the file.

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

# Operations

## Start / Stop

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

## Import Test

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

## Integration

### General

This version of the Adapter integrates with provider systems via the
import and export of text files in the CSV format (comma-separated
values, see http://en.wikipedia.org/wiki/Comma-separated_values).

CSV files must end with a `.txt` or `.csv` extension to be recognized.

The Adapter import and export are configured (in
`c:\adapter\config\adapter_sync.yml`) as follows:

-   `import_folder\`
    Directory where importable files will be found (default:
    `c:\adapter\tmp\import`).
-   `completed_folder\`
     Where files will be moved to after they are imported and where the
    import.log file will appear, detailing the results of the import
    (default: `c:\adapter\tmp\import_done`).
-   `export_folder\`
     Where new data received from the Clearinghouse will be exported
    (default: `c:\adapter\tmp\export`).

This guide assumes familiarity with the Ride Clearinghouse and related
terminology (trip tickets, trip claims, trip results).

### Working with Array and Hstore (Hash) Fields

The Clearinghouse stores several customer identifier fields as either
array or hstore (hash) datatypes. These fields use specific formatting 
when being stored in a CSV file, and you will need to account for this
when preparing tickets from your local database for export to the API,
and when importing Clearinghouse data back into your local database.

#### Array Field Representation

Array fields are represented in CSV in the following format:

```
customer_mobility_factors
"{""customer_mobility_factor A"",""customer_mobility_factor B""}"
```

Note the curly braces (`{` and `}`) that wrap the expression, and the
escaped quotes (`""`) that wrap each item. Note also that there are no
spaces before or after the delimiting comma.

#### Hstore (hash) Field Representation

Hstore fields are represented in CSV in the following format:

```
customer_identifiers
"""customer_identifier A""=>""customer_identifier B"",""customer_identifier C""=>""customer_identifier D"""
```

Note that there are NO braces that wrap the whole expression. Both keys
and values are wrapped in escaped quotes (`""`). Use `=>` to separate
keys and values, and commas to separate pairs. Note that there are no
spaces before or after the `=>` or the delimiting comma.

### Share a Trip Ticket with the Clearinghouse

When a provider cannot fulfill a trip and wish to share it in the Ride
Clearinghouse for other providers to claim, they would typically enter
the trip ticket to be shared on the Clearinghouse web site. Using the
Adapter, a trip ticket could be posted to the Clearinghouse by placing
it in a CSV-formatted text file, then dropping the text file in the
Adapter’s configured import directory.

The following is an example of a trip ticket in CSV format, ready to be
imported (note that this trip ticket does not contain all of the
required data fields for a new trip – it is shortened for readability):

```
origin_trip_id,customer_first_name,customer_last_name,appointment_time
"1234","Bob","Smith","2013-07-01 13:00"
```

A separate document will contain the complete specifications for allowed
and required fields, formats, and exported files.

### Send Changes to a Shared Trip Ticket

Changes to a trip ticket that was previously shared is relatively
simple. This just requires a row in a CSV file that includes the changed
values. The fields `origin_trip_id` and `appointment_time` are required
for matching, so the original trip is updated and a new trip is not
created.

### Receive New and Changed Trip Tickets

When the Adapter polls the first time, it creates a local copy of all
Clearinghouse trip tickets originated by your company. This allows the
Adapter to determine which imported trips are new trips vs. updates, and
also allows the Adapter to identify changes that occurred on the
Clearinghouse and should be reported locally.

This reporting is accomplished by exporting all new trips and trip
changes seen on the Clearinghouse to a file in the configured export
folder. The file will be named `trip_tickets.yyyy-mm-dd.hhmmss.csv` 
where `yyyy-mm-dd` is the current date and hhmmss is the time the file
was created.

### Receive Claims, Comments, and Results

The same way new and modified trip tickets are exported to the export
folder, new and modified trip ticket claims, comments, and results are
also exported to files named:

-   `trip_claims.yyyy-mm-dd.hhmmss.csv`
-   `trip_ticket_comments.yyyy-mm-dd.hhmmss.csv`
-   `trip_results.yyyy-mm-dd.hhmmss.csv`

### Receive Claimed Trip Tickets

When your company submits a claim on a trip ticket on the Clearinghouse
web site, your Adapter will then download and export a copy of that trip
ticket, its associated claims and comments, and updates. This allows you
to track any changes to the trip you have claimed, for example if it was
cancelled or the appointment time was changed. This also allows you to
receive notification when your claim is approved or declined.

### Send Trip Results to the Clearinghouse

When a trip you have successfully claimed has been fulfilled or
otherwise completed, one would typically enter the trip result on the
Clearinghouse. Trip results can be sent to the Clearinghouse via CSV
import by including them as updates to the claimed trip. The CSV file
must contain the origin_trip_id and appointment_time fields so the
existing trip can be matched.

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

-   The Adapter may encounter problems while importing new data to send
    to the Clearinghouse, or while using the Clearinghouse service APIs
    to exchange data. In the former case, the data that caused the
    errors will be skipped and a message will be received similar to:
    “Encountered {\#} errors while importing file {name} at {time}”
    followed by the error description. The import log (see section
    entitled *Logging*) will contain the error details to assist in
    correcting the import data format.
-   When Clearinghouse service errors are encountered, a notification
    will be sent containing a message similar to: “Encountered {\#}
    errors while syncing with the Ride Clearinghouse” followed by the
    error description. Details on these errors will be located in
    c:\adapter\log\adapter_sync.log.

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
main worker process. 

#### Log Messages

The Adapter Sync Log contains detailed debugging information including
database operations. The complete list of logged messages cannot be
covered here. Typical log messages useful in identifying normal
operation are as follows:

-   Retrieved [\#] updated trips from API\
     The Adapter has found trip tickets on the Clearinghouse server that
    are new, updated, or have new comments, claims, or results added.
-   Import folder not configured, will not check for files to import\
     Import folder is not configured in
    `c:\adapter\config\adapter_sync.yml.`
-   Import folder [directory name] does not exist\
     The import folder configured in
    `c:\adapter\config\adapter_sync.yml` is not a valid directory or
    inaccessible to the Adapter.
-   Starting import from directory [directory name] with output
    directory [directory name]
-   Skipping file [file name] which was previously imported
-   Imported [\#] files\
     This will be followed by the results for each file that was
    imported.
-   Export folder not configured, will not export new changes detected
    on the Clearinghouse\
     Export folder is not configured in
    `c:\adapter\config\adapter_sync.yml.`
-   Export folder [directory name] does not exist\
     The import folder configured in
    `c:\adapter\config\adapter_sync.yml` is not a valid directory or
    inaccessible to the Adapter.
-   Error notification failed, could not send email: [email contents]\
     There is a problem with sending emails from the Adapter. Check
    email notification configuration in `c:\adapter\config\mail.yml`.

### Import Log

Located in: `c:\adapter\tmp\import_done\import.log`

A detailed account of data import operations including any errors
encountered. This file may be in a different folder if you change the
value of `completed_folder` in `config/adapter_sync.yml`.

#### Normal Log Messages

-   Starting import from directory [directory name]
-   Found [\#] files to import
-   File [file name] skipped\
     This indicates that the file was previously imported and will be
    skipped until its file name or contents are changed.
-   Importing [file name]
-   Processing [\#] rows
-   Row [\#] data: [row data]
-   Row [\#] error: [error message]
-   POST trip ticket with API, result [server API response]\
     The import process created a new trip on the Clearinghouse server.
-   PUT trip ticket with API, result [server API response]\
     The import process updated an existing trip on the Clearinghouse
    server.
-   Successfully imported [\#] rows, [\#] rows had errors and could not
    be processed\
     The rows that could not be imported will be detailed in the log. If
    they need to be imported, they will need to be fixed and included in
    a new import file.

#### Common Error Messages

-   Imported row does not contain an origin_trip_id value\
     This indicates that the imported row is missing it’s required
    origin_trip_id field.
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
-   Error marking file as imported, please make sure Adapter has
    read-write access to [file name]\
     The Adapter attempts to rename or move imported files so they are
    not imported again. If this cannot be done, file permissions may be
    preventing the Adapter from modifying the file.
-   Error marking file as imported with errors, please make sure Adapter
    has read-write access to [file name]\
     In case of an unexpected error that the Adapter cannot recover
    from, the import file will be renamed with a `.error` extension to
    prevent repeated attempts to import a bad file. If this cannot be
    done, file permissions may be preventing the Adapter from modifying
    the file.

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
