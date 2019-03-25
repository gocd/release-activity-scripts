require_relative '../lib/env_reader'
require_relative '../lib/version_file_reader'
require_relative '../lib/version_validator'

def build_repo_url(user, password, repo_owner, repo_name)
  if user.to_s.empty? && password.to_s.empty?
    "https://github.com/#{repo_owner}/#{repo_name}"
  else
    "https://#{user}:#{password}@github.com/#{repo_owner}/#{repo_name}"
  end
end

desc 'Bump versions of pg and bc addons for each release'
task :bump_extensions_doc_version do
  previous_version   = VersionFileReader.previous_version || Env.get_or_error('PREVIOUS_VERSION')
  github_token       = Env.get('GITHUB_TOKEN')
  github_username    = Env.get('GITHUB_USER')
  org                = Env.get('TEST_ORG') || 'gocd-private'
  version_to_release = VersionFileReader.go_version || Env.get_or_error('VERSION_TO_RELEASE')
  repo_url           = build_repo_url(github_username, github_token, org, 'extensions-docs.gocd.org')

  VersionValidator.validate_format(previous_version)
  VersionValidator.validate_format(version_to_release)

  puts "\n=========================================================================================="
  puts "- Version to release   : #{version_to_release}"
  puts "- Previous version     : #{previous_version}"
  puts "- GitHub repository url: #{repo_url}"
  puts "==========================================================================================\n\n"

  rm_rf 'build'
  sh("git clone #{repo_url} build --branch master --depth 1 --quiet")

  cd 'build' do
    ['postgresql', 'business-continuity'].each do |addon|

      unless File.exists?("source/#{addon}/#{version_to_release}")
        sh("cp -r source/#{addon}/#{previous_version} source/#{addon}/#{version_to_release}")

        all_versions_file      = "data/plugins/#{addon}/versions/all.json"
        relative_versions_file = "data/plugins/#{addon}/versions/relative.json"

        versions          = JSON.parse(File.read(all_versions_file))
        relative_versions = JSON.parse(File.read(relative_versions_file))
        versions << version_to_release

        versions = versions.uniq.sort_by do |v|
          ::Gem::Version.new(v)
        end.reverse

        relative_versions['current'] = version_to_release

        open(all_versions_file, 'w') {|f| f.write(JSON.pretty_generate(versions))}

        open(relative_versions_file, 'w') {|f| f.write(JSON.pretty_generate(relative_versions))}

      end

      sh("git add source/#{addon}/#{version_to_release} data/plugins/#{addon}/versions")
    end

    sh("git commit -m 'Bump version to #{version_to_release}'")
    sh("git push #{repo_url} master")
  end
end
