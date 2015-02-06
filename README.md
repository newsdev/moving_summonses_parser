Moving Summonses Parser
================

New York Police Department Moving Summons Statistics Scraper & Parser
----------------------------------------------------------------

This collection of tools scrapes the [N.Y.P.D.'s Traffic Summons data page](http://www.nyc.gov/html/nypd/html/traffic_reports/traffic_summons_reports.shtml), downloads the moving summons stats that are published per month per precinct there, then parses them into actual data.

This tool is designed to minimally output a CSV with current-month moving summons data, but more advanced options are available.

After you install this tool (see below), you will be able to download the most recent PDFs from the NYPD's site and generate a CSV.

Installation
--------------

Run the commands following a `$` on the command line (like Terminal on a Mac). This assumes you have a Ruby version manager (like (RVM)[https://rvm.io/] or [rbenv](https://github.com/sstephenson/rbenv)) and MySQL already installed on your machine.

````
$ git clone git@github.com:nytinteractive/moving_summonses.git
$ cd moving_summonses
$ rbenv install jruby-1.7.16 # or another recent JRuby version
$ rbenv local jruby-1.7.16
$ create database moving_summonses # creates a database in MySQL called "moving_summonses"
````

Optionally, fill in config.yml (based on the details in config.example.yml) if you want a database or PDFs saved to S3 (See the "Configuration Options" section below for more information.)

````
$ bundle install
$ moving_summons_scraper.rb MONTH YEAR #once the scraper is installed, execute it
````


Usage
------

- `$ compstat_scraper.rb 2 2015` (takes 2 arguments, month, then year) Scrapes the most recent PDFs from the NYPD site. NOTE: You have to supply the current month and year of the PDFs on the NYPD's site. The script needs you to tell it correctly, or else the stats will be assigned to the wrong month/year.

Also, note that if you run the script multiple times without a database, rows will be duplicated in the CSV. You should dedupe it with UNIX's `uniq` tool, in Sublime Text or in Excel.

Advanced Options
=================
This tool can also interface with Amazon S3 for storage of PDFs and MySQL (or RDS) for stats. These options are set in a config file, `config.yml`. 

Depending on whether you're trying to parse locally-stored old PDFs or scrape and parse the N.Y.P.D.'s most current, this library supplies two additional executables (in src/bin/) : 

- `parse_local_moving_summons_reports.rb` (takes any number of arguments -- globs or folder paths that should be parsed) Scrapes data from locally-downloaded PDFs e.g. `ruby /bin/parse_local_compstat_pdfs.rb  "../pdfs/"`
- `moving_summons_scraper.rb` (takes no arguments) Scrapes the most recent PDFs from the NYPD site.
- `parse_moving_summons_reports_from_s3.rb` (takes one optional argument, a "prefix" to PDFs in the S3 bucket)



Configuration options
---------------------

See config.example.yml for a working example, or:
````
---
aws:
  access_key_id: whatever
  secret_access_key: whatever
  s3:
    bucket: mybucket
    bucket_path: moving_summonses
  sns:
    topic_arn: arn:aws:sns:region:1234567890:topic-nmae
mysql:
  host: localhost
  username: root
  password:
  port: 
  database: moving_summonses
local_pdfs_path: false
csv: 'moving_summons_stats.csv'
````

When any of these options are unspecified, they will be silently ignored. (However, if the settings are invalid, an error will be thrown.) For instance, if the `mysql` block isn't supplied, data will not be sent to MySQL; if AWS is unspecified, PDFs will not be uploaded to S3 and `status_checker.rb` will not send notifications by email. An exception is the `csv` key: if this is unset, data will be saved to `moving_summons_stats.csv`; set it to "false" or 0 to prevent any CSV from being generated.

If MySQL is specified in the config file, two tables will be created (or appended to, if they already exist) in the specified database: `moving_violations_by_precinct` and `moving_violations_citywide`. The record layout for each table is identical: citywide summaries are located in `moving_violations_by_precinct` and precinct-by-precinct data is in `moving_violations_citywide`.


DOCKER and boot2docker
------------------------
````
cd ./src
docker build movingsummonses .
docker run -it movingsummonses bundle exec jruby bin/moving_summons_scraper.rb
````

Export from MySQL to CSV:
-------------------------
To export from MySQL to CSV: 
````
mysql compstat -e "select * from crimes_by_precinct" | sed 's/	/","/g;s/^/"/;s/$/"/;s/\n//g' > crime_stats_from_mysql.csv
````
taking care to ensure that the first regex is a real tab. (If on Mac/BSD; on Unix, \t is fine.)



Want to contribute?
-------------------

I welcome your contributions. If you have suggestions or issues, please register them in the Github issues page. If you'd like to add a feature or fix a bug, please open a Github pull request. Or send me an email, I'm happy to guide you through the process.

And, if you're using these, please let me know. I'd love to hear from you!
