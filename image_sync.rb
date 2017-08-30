#!/usr/bin/env ruby

require 'find'
require 'digest/md5'
require 'logger'
require 'tmpdir'
require 'rsync'

def missing_env_vars?
  return (ENV['IM_DESTINATION'].nil? || ENV['IM_VOLATILE'].nil? || ENV['IM_CANONICAL'].nil?)
end

def missing_args?
  return (ARGV[0].nil? || ARGV[1].nil?)
end

def valid_args?
  return (File.exist?(ARGV[0]))
end

def create_process_lock(namespace)
  begin
    pid_dir = "#{Dir.tmpdir()}.running_#{namespace}"
    pid_file = 'image_sync.pid'
    FileUtils.mkdir(pid_dir)
    File.open("#{pid_dir}/#{pid_file}", 'w') { |file| file.write('Process running') }
    return "#{pid_dir}/#{pid_file}", pid_dir
  rescue Errno::EEXIST
    abort("Process for #{namespace} already running")
  end
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
  return File.exist?(canonical_symlink) || File.symlink?(canonical_symlink)
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

def transform_collection_namespace(namespace)
  chars_array = namespace.chars.each_slice(2).map(&:join)
  single_index = chars_array.index{|char| char.length == 1 }
  unless single_index.nil?
    chars_array[single_index] = "#{chars_array[single_index]}_"
  end
  transformed_namespace = chars_array.join('/')
  return transformed_namespace
end

abort 'Missing env variable(s)' if missing_env_vars?
abort 'Missing command-line argument(s)' if missing_args?
abort 'Invalid comand-line argument(s)' unless valid_args?

image_source = ARGV[0]
destination_namespace = ARGV[1]

source = "#{image_source}/#{transform_collection_namespace(destination_namespace)}"

abort "Collection not found at #{source}" unless File.exist?(source)

destination = "#{ENV['IM_DESTINATION']}/#{destination_namespace}"
volatile = ENV['IM_VOLATILE']
canonical = ENV['IM_CANONICAL']

process_lock, process_directory = create_process_lock(destination_namespace)

logger = Logger.new('| tee logger.log')
logger.level = Logger::INFO
logger.info('Script run started')

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

    file = file_matched[0]

    logger.warn("More files match #{wfp} than expected in #{object}/#{version}, using (#{file}).") if file_matched.length > 1

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
      logger.warn("Pre-existing symlink in volatile directory -- replacing at #{volatile_file_path}")
      FileUtils.rm_rf(volatile_file_path, :secure => true)
      retry
    end

    if canonical_exists?(canonical_file_path)
      move_file = false
      if newer_version_available?(file, version, canonical_file_path)
        destination_file_path = "#{destination}/modify/#{dest_basename}"
        FileUtils.mkdir_p("#{destination}/modify/")
        move_file = true
        canonical_action = 'update'
      end
    else
      destination_file_path = "#{destination}/add/#{dest_basename}"
      FileUtils.mkdir_p("#{destination}/add/")
      move_file = true
      canonical_action = 'add'
    end

    if move_file
      logger.info("Initializing transfer for #{file.gsub(source, '')}")
      Rsync.run(file, destination_file_path, "-lptv") do |result|
        if result.success?
          logger.info("Transfer succeeded for #{file.gsub(source, '')}")
          manage_canonical_symlink(file, canonical_file_path, canonical_action)
          logger.info("#{canonical_action.upcase} - Canonical path (#{dest_dir}/#{dest_basename})")
        else
          logger.info("#{result.error} for #{file.gsub(source, '')}")
          exit
        end
      end

    end

  end

  # known_ignored_file_patterns.each do |ifp|
    #TODO: Version but do not transfer
  # end

end

# Optionally clear out the volatile directory at the end of the run
FileUtils.rm_rf(Dir.glob("#{volatile}/*"), :secure => true)

# Unlock the process
FileUtils.rm_rf(process_directory, :secure => true)

logger.info('Script run complete')
