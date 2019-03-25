require 'json'
require_relative 'env_reader'

class VersionFileReader
  def self.go_version
    read 'go_version'
  end

  def self.go_full_version
    read 'go_full_version'
  end

  def self.go_build_number
    read 'go_build_number'
  end

  def self.git_sha
    read 'git_sha'
  end

  def self.next_version
    read 'next_go_version'
  end

  private
  def self.read key
    version_file_location = Env.get('VERSION_FILE_LOCATION') || 'version.json'
    if File.exist?(version_file_location)
      value = JSON.parse(File.read(version_file_location))[key]
      return value.to_s.empty? ? nil : value
    end
    return nil
  end
end