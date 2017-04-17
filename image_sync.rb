#!/usr/bin/env ruby

require 'find'
require 'digest/md5'
require 'pry'

def missing_env_vars?
  return (ENV['IM_SOURCE'].nil? || ENV['IM_DESTINATION'].nil? || ENV['IM_VOLATILE'].nil? || ENV['IM_CANONICAL'].nil?)
end

def check_version(incoming_target, latest_version, canonical_symlink)
  target = File.readlink(canonical_symlink)
  return false if incoming_target == target
  abort("Version specified in current.txt (#{latest_version}) does not match incoming symlink target") unless incoming_target.include?(latest_version)
  return true if incoming_target.include?(latest_version)
end

def update_target(latest_target, canonical_symlink)
  FileUtils.ln_sf(latest_target, canonical_symlink)
end

abort 'Missing env variable(s)' if missing_env_vars?

source = ENV['IM_SOURCE']
destination = ENV['IM_DESTINATION']
volatile = ENV['IM_VOLATILE']
canonical = ENV['IM_CANONICAL']

whitelisted_file_patterns = ['^.*DELIVERY.jp2']
known_ignored_file_patterns = ['^.*THUMB.jp2','encoding.log']

# This file will always be in the top directory of each image for processing
identity_file = '0=dflat_1.0'

objects = Find.find(source).select { |p| /#{identity_file}/ =~ p }

objects.each { |obj| obj.gsub!(identity_file,'').chomp!('/') }

objects.each do |object|

  version = File.open("#{object}/current.txt").readlines.first.chomp
  files = Dir["#{object}/#{version}/full/*"]

  whitelisted_file_patterns.each do |wfp|

    move_file = false

    file_matched = files.select { |p| /#{wfp}/ =~ p }

    abort("no whitelisted files detected in #{object}/#{version}") if file_matched.length > 1 || file_matched.empty?

    file = file_matched[0]

    basename = File.basename(file, '.*')
    basename = basename.split('.').first

    dest_basename = "#{basename}.jp2"
    dest_name_md5 = Digest::MD5.hexdigest(dest_basename)

    dest_dir = "#{dest_name_md5[0..2]}"

    volatile_file_path = "#{volatile}/#{dest_dir}/#{dest_basename}"
    canonical_file_path = "#{canonical}/#{dest_dir}/#{dest_basename}"
    destination_file_path = "#{destination}/#{dest_dir}/#{dest_basename}"

    FileUtils.mkdir_p("#{volatile}/#{dest_dir}")
    FileUtils.mkdir_p("#{canonical}/#{dest_dir}")
    FileUtils.mkdir_p("#{destination}/#{dest_dir}")

    begin
      FileUtils::ln_s(file, volatile_file_path)
    rescue
      abort('Volatile directory not empty')
    end

    begin
      FileUtils.ln_s(file, canonical_file_path)
      move_file = true
    rescue => exception
      if check_version(file, version, canonical_file_path)
        update_target(file, canonical_file_path)
        destination_file_path = "#{destination}/#{dest_dir}/modify/#{dest_basename}"
        FileUtils.mkdir_p("#{destination_file_path}")
        move_file = true
      end
    end

    FileUtils.rm_rf(Dir.glob("#{volatile}/*"), :secure => true)

    `rsync -lptv "#{file}" "#{destination_file_path}"` if move_file

  end

  # known_ignored_file_patterns.each do |ifp|
    #TODO: Version but do not transfer
  # end

end

