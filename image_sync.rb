#!/usr/bin/env ruby

require 'find'
require 'digest/md5'
require 'pry'

def missing_env_vars?
  return (ENV['IM_SOURCE'].nil? || ENV['IM_DESTINATION'].nil? || ENV['IM_VOLATILE'].nil? || ENV['IM_CANONICAL'].nil?)
end

whitelisted_file_patterns = ['^.*DELIVERY.jp2']
known_ignored_file_patterns = ['^.*THUMB.jp2','encoding.log']

# This file will always be in the top directory of each image for processing
identity_file = '0=dflat_1.0'

abort 'Missing env variable(s)' if missing_env_vars?

source = ENV['IM_SOURCE']
dest = ENV['IM_DESTINATION']
volatile = ENV['IM_VOLATILE']
canonical = ENV['IM_CANONICAL']

objects = Find.find(source).select { |p| /#{identity_file}/ =~ p }

objects.each { |obj| obj.gsub!(identity_file,'').chomp!('/') }

objects.each do |object|

  version = File.open("#{object}/current.txt").readlines.first.chomp
  files = Dir["#{object}/#{version}/full/*"]

  whitelisted_file_patterns.each do |wfp|
    file_matched = files.select { |p| /#{wfp}/ =~ p }

    abort("no whitelisted files detected in #{files}") if file_matched.length > 1 || file_matched.empty?

    file = file_matched[0]

    basename = File.basename(file, '.*')
    basename = basename.split('.').first


    dest_basename = "#{basename}.jp2"
    dest_name_md5 = Digest::MD5.hexdigest(dest_basename)

    dest_dir = "#{dest_name_md5[0..2]}"

    FileUtils.mkdir_p("#{dest}/#{dest_dir}")



    `rsync -lptv "#{file}" "#{dest}/#{dest_dir}/#{dest_basename}"`

  end

end

