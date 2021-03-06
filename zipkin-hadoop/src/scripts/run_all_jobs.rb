#!/usr/bin/env ruby
# Copyright 2012 Twitter Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runs all scalding jobs in package com.twitter.zipkin.hadoop

require 'optparse'
require 'ostruct'
require 'pp'
require 'date'
require 'run_job'

class OptparseAllJobArguments

  #
  # Return a structure describing the options.
  #
  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.uses_hadoop_config = false
    options.dates = []
    options.output = ""

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: run_job.rb -d DATE -o OUTPUT -c CONFIG"

      opts.separator ""
      opts.separator "Specific options:"

     opts.on("-d", "--date STARTDATE,ENDDATE", Array, "The DATES to run the jobs over.  Expected format for dates are is %Y-%m-%d") do |list|
        options.dates = list.map{|date| DateTime.strptime(date, '%Y-%m-%d')}
      end

      opts.on("-o", "--output OUTPUT",
              "The OUTPUT file to write to") do |output|
        options.output = output
      end
      
      opts.on("-c", "--config [CONFIG]", "Optional hadoop configurations for the job.") do |config|
        options.uses_hadoop_config = true
        options.hadoop_config = config || ''
      end

      opts.separator ""
      opts.separator "Common options:"      
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
    opts.parse!(args)
    options
  end
end

#Run the commands

def run_jobs_in_parallel(prep, jobs)
  threads = []
  prepThread = Thread.new(prep) { |prep| run_job(prep) }
  for job in jobs 
    threads << Thread.new(job) { |job| run_job(job) }
  end
  prepThread.join
  return threads
end

def run_all_jobs(dates, output, hadoop_config)
  uses_hadoop_config = hadoop_config != nil
  config_string = uses_hadoop_config ? " --config " + hadoop_config : nil

  jobs_set_1 = []

  jobs_set_2 = Array[JobArguments.new(dates, nil, config_string, "UTC", "PopularKeys", output + "/PopularKeys", false),
       JobArguments.new(dates, nil, config_string, "UTC", "PopularAnnotations", output + "/PopularAnnotations", false),
       JobArguments.new(dates, nil, config_string, "UTC", "MemcacheRequest", output + "/MemcacheRequest",false),
       JobArguments.new(dates, nil, config_string, "UTC", "WorstRuntimes", output + "/WorstRuntimes", false),
       JobArguments.new(dates, nil, config_string, "UTC", "WorstRuntimesPerTrace", output + "/WorstRuntimesPerTrace", false),
       JobArguments.new(dates, nil, config_string, "UTC", "WhaleReport", output + "/WhaleReport", false)]

  jobs_set_3 = Array[JobArguments.new(dates, nil, config_string, "UTC", "DependencyTree", output + "/DependencyTree", false),
       JobArguments.new(dates, nil, config_string, "UTC", "ExpensiveEndpoints", output + "/ExpensiveEndpoints", false),
       JobArguments.new(dates, "\" --error_type finagle.timeout \"", config_string, "UTC", "Timeouts", output + "/Timeouts", false),
       JobArguments.new(dates, " \" --error_type finagle.retry \"", config_string, "UTC", "Timeouts", output + "/Retries", false),]
  
  run_job(JobArguments.new(dates, nil, config_string, "UTC", "DailyPreprocessed", nil, true))

  jobs = run_jobs_in_parallel(JobArguments.new(dates, nil, config_string, "UTC", "DailyFindNames", nil, true), jobs_set_1)
  jobs += run_jobs_in_parallel(JobArguments.new(dates, nil, config_string, "UTC", "DailyFindIDtoName", nil, true), jobs_set_2)
  jobs += run_jobs_in_parallel(nil, jobs_set_3)
  
  jobs.each { |aThread| aThread.join }

  puts "All jobs finished!"
end

if __FILE__ == $0
  options = OptparseAllJobArguments.parse(ARGV)
  run_all_jobs(options.dates, options.output, options.hadoop_config)
end
