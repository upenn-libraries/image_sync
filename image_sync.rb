#!/usr/bin/env ruby

require 'find'
require 'digest/md5'
require 'pry'

def missing_env_vars?
  return (ENV['IM_SOURCE'].nil? || ENV['IM_DESTINATION'].nil? || ENV['IM_VOLATILE'].nil? || ENV['IM_CANONICAL'].nil?)
end

def whitelisted_files_present?(file_list, whitelisted_file_patterns)
  indicator = false
  whitelisted_file_patterns.each do |wfp|
    file_list.select do |p|
      indicator = true unless (/#{wfp}/ =~ p).nil?
    end
  end
  return indicator
end

def canonical_exists?(canonical_symlink)
  return File.exist?(canonical_symlink)
end

def newer_version_available?(incoming_target, latest_version, canonical_symlink)
  target = File.readlink(canonical_symlink)
  return false if incoming_target == target
  abort("Version specified in current.txt (#{latest_version}) does not match incoming symlink target") unless incoming_target.include?(latest_version)
  return true if incoming_target.include?(latest_version)
end

def update_target(latest_target, canonical_symlink)
  FileUtils.ln_sf(latest_target, canonical_symlink)
end

def manage_canonical_symlink(target, canonical_symlink, canonical_action)
  update_target(target, canonical_symlink) if canonical_action == 'update'
  FileUtils.ln_s(target, canonical_symlink) if canonical_action == 'add'
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

  move_file = false

  version = File.open("#{object}/current.txt").readlines.first.chomp
  files = Dir["#{object}/#{version}/full/*"]

  next unless whitelisted_files_present?(files, whitelisted_file_patterns)

  whitelisted_file_patterns.each do |wfp|

    file_matched = files.select { |p| /#{wfp}/ =~ p }

    abort("More files match #{wfp} than expected in #{object}/#{version}, aborting.") if file_matched.length > 1

    file = file_matched[0]

    basename = File.basename(file, '.*')
    basename = basename.split('.').first

    dest_basename = "#{basename}.jp2"
    dest_name_md5 = Digest::MD5.hexdigest(dest_basename)

    dest_dir = "#{dest_name_md5[0..2]}"

    volatile_file_path = "#{volatile}/#{dest_dir}/#{dest_basename}"
    canonical_file_path = "#{canonical}/#{dest_dir}/#{dest_basename}"

    FileUtils.mkdir_p("#{volatile}/#{dest_dir}")
    FileUtils.mkdir_p("#{canonical}/#{dest_dir}")

    begin
      FileUtils::ln_s(file, volatile_file_path)
    rescue
      abort('Conflicting symlink in volatile directory')
    end

    if canonical_exists?(canonical_file_path)
      move_file = false
      if newer_version_available?(file, version, canonical_file_path)
        destination_file_path = "#{destination}/modify/#{dest_dir}/#{dest_basename}"
        FileUtils.mkdir_p("#{destination}/modify/#{dest_dir}")
        move_file = true
        canonical_action = 'update'
      end
    else
      destination_file_path = "#{destination}/add/#{dest_dir}/#{dest_basename}"
      FileUtils.mkdir_p("#{destination}/add/#{dest_dir}")
      move_file = true
      canonical_action = 'add'
    end

    FileUtils.rm_rf(Dir.glob("#{volatile}/*"), :secure => true)

    if move_file
      `rsync -lptv "#{file}" "#{destination_file_path}"`
      manage_canonical_symlink(file, canonical_file_path, canonical_action)
    end

  end

  # known_ignored_file_patterns.each do |ifp|
    #TODO: Version but do not transfer
  # end

end

