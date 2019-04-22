require 'json'
require 'erb'
require_relative '../lib/env_reader'
require_relative '../lib/version_file_reader'
require_relative '../lib/version_validator'

desc "bump version"

def build_version_json(repo_name, version, type)
  version_json        = {
      version:  version,
      location: "https://#{repo_name}/#{version}/",
  }
  version_json[:type] = type if type
  version_json
end

def get_existing_versions_info(repo_name, version_to_release)
  if File.exist?('versions.json')
    JSON.parse(File.read('versions.json'), symbolize_names: true)
  else
    available_versions = Dir['*'].reject {|f| !File.directory?(f)}.collect {|f| Gem::Version.new(f) rescue nil}.compact.sort.reverse.collect(&:to_s)
    versions           = [build_version_json(repo_name, version_to_release, 'next')]
    available_versions.each_with_index do |version, i|
      versions << build_version_json(repo_name, version, ('latest' if i == 0))
    end
    versions
  end
end

def update_latest_and_next_version_in_version_json_file(repo_name, version_to_release, next_version)
  versions = get_existing_versions_info(repo_name, version_to_release)

  versions.delete_if do |version_data|
    version_data[:version] == next_version
  end

  versions.each do |version_data|
    version_data.delete(:type)

    if version_data[:version] == version_to_release
      version_data[:type] = 'latest'
    end
  end

  versions.unshift(build_version_json(repo_name, next_version, 'next'))
  open('versions.json', 'w') {|f| f.puts(JSON.pretty_generate(versions))}
  versions
end

def sort_by_version(current_version, version_to_release, next_version)
  [Gem::Version.new(current_version), Gem::Version.new(version_to_release), Gem::Version.new(next_version)].sort.collect(&:to_s)
end

def build_repo_url(user, password, repo_owner, repo_name)
  if user.to_s.empty? && password.to_s.empty?
    "https://github.com/#{repo_owner}/#{repo_name}"
  else
    "https://#{user}:#{password}@github.com/#{repo_owner}/#{repo_name}"
  end
end

def git_push
  if Env.get('FORCE_PUSH') == 'true'
    "git push -f"
  else
    "git push"
  end
end

current_version_file_location = {
    'api.go.cd'        => {dir: 'lib', file: 'version.rb'},
    'plugin-api.go.cd' => {dir: 'lib', file: 'version.rb'},
    'docs.go.cd'       => {dir: 'rakelib', file: 'version.rake'},
    'developer.go.cd'  => {dir: 'rakelib', file: 'version.rake'}
}

task :bump_docs_version do
  repo_owner         = Env.get_or_error('ORG')
  repo_name          = Env.get_or_error('REPO_NAME')
  github_token       = Env.get('GITHUB_TOKEN')
  github_username    = Env.get('GITHUB_USER')
  next_version       = VersionFileReader.next_version
  version_to_release = VersionFileReader.go_version

  puts "\n=========================================================================================="
  puts "- Version to release          : #{version_to_release}"
  puts "- Next version                : #{next_version}"
  puts "- GitHub organization or user : #{repo_owner}"
  puts "- GitHub repository           : #{repo_name}"
  puts "==========================================================================================\n\n"

  repo_url = build_repo_url(github_username, github_token, repo_owner, repo_name)
  $stderr.puts "*** Setting up gh-pages branch for next release"

  rm_rf 'build'
  sh("git clone #{repo_url} build --branch gh-pages --depth 1 --quiet")

  current_version = File.readlink('build/current')

  if sort_by_version(current_version, version_to_release, next_version) != [current_version, version_to_release, next_version]
    fail 'CURRENT_VERSION VERSION_TO_RELEASE and NEXT_VERSION don\'t seem right'
  end

  cd 'build' do
    rm 'current'
    ln_sf version_to_release, './current'
    versions = update_latest_and_next_version_in_version_json_file(repo_name, version_to_release, next_version)

    open('index.html', 'w') do |f|
      erb  = ERB.new(File.read("#{File.dirname(__FILE__)}/../templates/#{repo_name}.index.html.erb"), nil, '-')
      html = erb.result(binding)
      f.puts(html)
    end

    open('robots.txt', 'w') do |f|
      erb  = ERB.new(File.read("#{File.dirname(__FILE__)}/../templates/robots.txt.erb"), nil, '-')
      html = erb.result(binding)
      f.puts(html)
    end

    response = %x[git status]
    unless response.include?('nothing to commit')
      sh("git add current versions.json index.html robots.txt")
      sh("git commit -m 'Add new version to dropdown'")
      sh(git_push)
    end
  end

  rm_rf 'build'
  sh("git clone #{repo_url} build --branch master --depth 1 --quiet")
  cd 'build' do
    $stderr.puts("*** Creating branch for - #{version_to_release}")
    sh("git checkout -b release-#{version_to_release}")
    sh("#{git_push} #{repo_url} release-#{version_to_release}")
    sh("git checkout master")

    version_file = current_version_file_location[repo_name]
    $stderr.puts "Bumping version in #{version_file[:dir]}/#{version_file[:file]}"
    mkdir(version_file[:dir]) unless Dir.exist?(version_file[:dir])
    open("#{version_file[:dir]}/#{version_file[:file]}", 'w') do |f|
      f.puts("# this file is updated automatically using a rake task, any changes will be lost")
      f.puts("GOCD_VERSION = '#{next_version}'")
    end

    response = %x[git status]
    unless response.include?('nothing to commit')
      sh("git add #{version_file[:dir]}/#{version_file[:file]}")
      sh("git commit -m 'bump version to #{next_version}'")
      sh("#{git_push} #{repo_url} master")
    end
  end
end